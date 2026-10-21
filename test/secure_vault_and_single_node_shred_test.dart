// test/secure_vault_and_single_node_shred_test.dart

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/subscription/config_generator.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';

// 測試用模擬安全儲存實作
class MockSecureStorage extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _data[key];
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> saveToken(String token) async => write('v2board_jwt_token', token);
  @override
  Future<String?> getToken() async => read('v2board_jwt_token');
  @override
  Future<void> deleteToken() async => delete('v2board_jwt_token');

  @override
  Future<void> saveEncryptedNodes(String rawYaml) async => write('v2board_encrypted_nodes_vault', rawYaml);
  @override
  Future<String?> getEncryptedNodes() async => read('v2board_encrypted_nodes_vault');
  @override
  Future<void> deleteEncryptedNodes() async => delete('v2board_encrypted_nodes_vault');

  @override
  Future<void> clearAll() async {
    _data.clear();
  }
}

// 模擬生成 26 顆節點的 YAML 資料 (包含 ANYTLS、VLESS 等)
String _generateMock26NodesYaml() {
  final sb = StringBuffer();
  sb.writeln('proxies:');
  for (int i = 1; i <= 26; i++) {
    final country = i <= 6 ? '🇯🇵 日本' : (i <= 12 ? '🇸🇬 新加坡' : (i <= 18 ? '🇭🇰 香港' : '🇺🇸 美國'));
    final type = i % 2 == 1 ? 'anytls' : 'vless';
    sb.writeln('  - name: "$country $i | ${type.toUpperCase()}"');
    sb.writeln('    type: $type');
    sb.writeln('    server: 104.21.$i.$i');
    sb.writeln('    port: 443');
    sb.writeln('    uuid: 12345678-1234-1234-1234-1234567890$i');
    sb.writeln('    tls: true');
  }
  return sb.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSecureStorage mockStorage;
  late AppConfigService mockConfigService;
  late DioClient mockDioClient;
  late CoreDaemon mockCoreDaemon;

  setUp(() {
    mockStorage = MockSecureStorage();
    mockConfigService = AppConfigService();
    mockDioClient = DioClient(configService: mockConfigService);
    mockCoreDaemon = CoreDaemon();
  });

  group('🏛️ 三層式加密快取 + 登入強同步保障 + 單節點閱後即焚架構測試', () {
    test('1. 首次登入強同步保障：拉取後 UI 保留全部 26 顆節點，並 100% 自動選中第 1 顆節點', () async {
      final dio = Dio();
      int callCount = 0;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          callCount++;
          return handler.resolve(Response(
            requestOptions: options,
            data: _generateMock26NodesYaml(),
            statusCode: 200,
          ));
        },
      ));

      final customDioClient = DioClient(
        configService: mockConfigService,
        customDio: dio,
      );

      final engine = SubscriptionEngine(
        dioClient: customDioClient,
        coreDaemon: mockCoreDaemon,
        storageService: mockStorage,
      );

      expect(engine.nodes.isEmpty, isTrue);
      expect(engine.selectedNode, isNull);

      // 首次登入觸發同步
      final nodes = await engine.syncSubscription(token: 'mock_jwt_token');

      expect(callCount, equals(1));
      // 驗證 UI 記憶體保留完整 26 顆節點
      expect(nodes.length, equals(26));
      expect(engine.nodes.length, equals(26));

      // 驗證 100% 自動預設選中第 1 顆有效節點
      expect(engine.selectedNode, isNotNull);
      expect(engine.selectedNode!.name, equals('🇯🇵 日本 1 | ANYTLS'));
      expect(engine.selectedNode!.protocol, equals('ANYTLS'));

      // 驗證本地金庫已加密落地存儲
      final vaultContent = await mockStorage.getEncryptedNodes();
      expect(vaultContent, isNotNull);
      expect(vaultContent!.contains('🇯🇵 日本 1 | ANYTLS'), isTrue);
    });

    test('2. 首次拉取網路波動：支援 3 次自動重試 (Auto-Retry) 機制', () async {
      final dio = Dio();
      int attempts = 0;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          attempts++;
          if (attempts < 3) {
            // 前 2 次模擬網路連線中斷
            return handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
              error: 'Connection timeout',
            ));
          } else {
            // 第 3 次成功返回
            return handler.resolve(Response(
              requestOptions: options,
              data: _generateMock26NodesYaml(),
              statusCode: 200,
            ));
          }
        },
      ));

      final customDioClient = DioClient(
        configService: mockConfigService,
        customDio: dio,
      );

      final engine = SubscriptionEngine(
        dioClient: customDioClient,
        coreDaemon: mockCoreDaemon,
        storageService: mockStorage,
      );

      final nodes = await engine.syncSubscription(
        token: 'mock_token',
        maxRetries: 3,
      );

      expect(attempts, equals(3));
      expect(nodes.length, equals(26));
      expect(engine.selectedNode?.name, equals('🇯🇵 日本 1 | ANYTLS'));
    });

    test('3. 本地加密金庫與 0 秒瞬開 (Stale-While-Revalidate)：重啟 App 瞬間解密還原全部節點', () async {
      // 預置加密金庫內容
      await mockStorage.saveEncryptedNodes(_generateMock26NodesYaml());
      await mockStorage.write('v2board_selected_node_id', '🇸🇬 新加坡 7 | ANYTLS');

      // 模擬重開 App，建立全新的 SubscriptionEngine 實例
      final engine = SubscriptionEngine(
        dioClient: mockDioClient,
        coreDaemon: mockCoreDaemon,
        storageService: mockStorage,
      );

      expect(engine.nodes.isEmpty, isTrue);

      // 第一步：從金庫還原 (0 秒瞬開)
      final restored = await engine.restoreFromVault();
      expect(restored, isTrue);

      // 驗證 UI 記憶體立即具備全部 26 顆節點
      expect(engine.nodes.length, equals(26));
      // 驗證成功還原先前選定之新加坡節點
      expect(engine.selectedNode?.name, contains('新加坡 7'));
    });

    test('4. 單節點動態切片 (Single-Node Slicing)：雖然 UI 有 26 顆節點，但 config.yaml 僅寫入 1 顆選中節點', () {
      final allNodes = ConfigGenerator.parseProxiesFromYaml(_generateMock26NodesYaml());
      expect(allNodes.length, equals(26));

      final selectedTarget = allNodes[5]; // 選取第 6 顆節點
      expect(selectedTarget.name, equals('🇯🇵 日本 6 | VLESS'));

      // 啟用 singleNodeSlice 生成核心 YAML
      final slicedYaml = ConfigGenerator.generateYaml(
        nodes: allNodes,
        selectedNodeName: selectedTarget.name,
        singleNodeSlice: true,
      );

      // 驗證 proxies 區段中只出現選中的那 1 顆節點
      expect(slicedYaml.contains('🇯🇵 日本 6 | VLESS'), isTrue);
      // 驗證其餘 25 顆節點絕不外洩至磁碟 YAML！
      expect(slicedYaml.contains('🇯🇵 日本 1 | ANYTLS'), isFalse);
      expect(slicedYaml.contains('🇸🇬 新加坡 7 | ANYTLS'), isFalse);
      expect(slicedYaml.contains('🇺🇸 美國 26 | VLESS'), isFalse);

      // 驗證 proxy-groups 策略組僅掛載此單一節點
      expect(slicedYaml.contains('- "🇯🇵 日本 6 | VLESS"'), isTrue);
    });

    test('5. 閱後即焚 (Read-and-Shred)：實體設定檔可覆寫並徹底抹除', () async {
      final tempDir = Directory.systemTemp.createTempSync('shred_test');
      final testFile = File('${tempDir.path}/config.yaml');
      await testFile.writeAsString('sensitive_proxies_content');

      expect(await testFile.exists(), isTrue);

      // 呼叫閱後即焚抹除
      await SubscriptionEngine.shredFile(testFile);

      expect(await testFile.exists(), isFalse);
      tempDir.deleteSync(recursive: true);
    });

    test('6. 登出與 401 踢出之會話清理：記憶體、金庫與沙盒 YAML 100% 徹底清除', () async {
      await mockStorage.saveEncryptedNodes(_generateMock26NodesYaml());
      await mockStorage.saveToken('jwt_test_token');

      final authManager = AuthManager(
        dioClient: mockDioClient,
        storageService: mockStorage,
      );

      final engine = SubscriptionEngine(
        dioClient: mockDioClient,
        coreDaemon: mockCoreDaemon,
        storageService: mockStorage,
      );

      // 還原至記憶體
      await engine.restoreFromVault();
      expect(engine.nodes.length, equals(26));
      expect(engine.selectedNode, isNotNull);

      // 綁定會話清理監聽
      authManager.addSessionClearedListener(() {
        engine.clearVaultAndMemory();
      });

      // 執行登出
      await authManager.logout();

      // 驗證記憶體節點已被清空
      expect(engine.nodes.isEmpty, isTrue);
      expect(engine.selectedNode, isNull);

      // 驗證本地金庫資料已被清空
      final vaultContent = await mockStorage.getEncryptedNodes();
      expect(vaultContent, isNull);
    });
  });
}
