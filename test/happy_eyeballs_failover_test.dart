// test/happy_eyeballs_failover_test.dart
// 驗收測試：去絕對網址化 + 2.5 秒極速直連 + 異常瞬間「全備援併發競速搶答下載 (Happy Eyeballs Failover)」

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/auth/user_model.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/constants/app_constants.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/remote_config_model.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';

String generate36NodesYaml() {
  final buffer = StringBuffer('proxies:\n');
  for (int i = 1; i <= 36; i++) {
    final country = (i <= 10)
        ? '🇭🇰 香港'
        : (i <= 20)
            ? '🇯🇵 日本'
            : (i <= 30)
                ? '🇺🇸 美國'
                : '🇸🇬 新加坡';
    buffer.writeln('  - name: "$country ${i.toString().padLeft(2, '0')} | 高速專線"');
    buffer.writeln('    type: vmess');
    buffer.writeln('    server: 1.1.$i.1');
    buffer.writeln('    port: 443');
    buffer.writeln('    uuid: "a1b2c3d4-e5f6-7890-abcd-${i.toString().padLeft(12, '0')}"');
    buffer.writeln('    alterId: 0');
    buffer.writeln('    cipher: auto');
  }
  return buffer.toString();
}

class _MockFailoverAdapter implements HttpClientAdapter {
  final void Function() on8219;
  final void Function() on8218;

  _MockFailoverAdapter({required this.on8219, required this.on8218});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = Uri.parse(options.path.startsWith('http') ? options.path : '${options.baseUrl}${options.path}');
    if (uri.host == '8.219.196.216') {
      on8219();
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'Connection refused to 8.219.196.216',
      );
    } else if (uri.host == '8.218.176.238') {
      on8218();
      return ResponseBody.fromString(
        json.encode({'status': 'ok', 'server': '8.218'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      error: 'Unknown host: ${uri.host}',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecureStorageService.isTestMode = true;

  group('【Happy Eyeballs 零感容災與去絕對網址化驗收矩陣】', () {
    late SecureStorageService storageService;
    late AppConfigService configService;

    setUp(() {
      storageService = SecureStorageService();
      configService = AppConfigService();
    });

    test('1. 【@Network 驗收】dio_client.dart 重試攔截器「絕對網址盲區」徹底修復測試', () async {
      // 模擬環境：初始 host 8.219 (掛掉)，備用 host 8.218 (正常)
      final candidateHosts = [
        'https://8.219.196.216:8443',
        'https://8.218.176.238:3389',
      ];
      configService.setCurrentApiDomain(candidateHosts.first);
      int attemptsTo8219 = 0;
      int attemptsTo8218 = 0;

      final customDio = Dio(
        BaseOptions(
          baseUrl: configService.currentApiDomain,
          connectTimeout: const Duration(milliseconds: 1000),
        ),
      );

      customDio.httpClientAdapter = _MockFailoverAdapter(
        on8219: () => attemptsTo8219++,
        on8218: () => attemptsTo8218++,
      );

      final client = DioClient(
        configService: configService,
        customDio: customDio,
      );

      // 發起以 8.219 為前綴的絕對網址請求 (模擬舊代碼或硬編碼死網址)
      final absoluteDeadUrl = 'https://8.219.196.216:8443/api/v1/user/info';
      final response = await client.get(absoluteDeadUrl);

      // 驗收：重試請求必須成功，且 options.path 的 host/port 100% 被替換為 8.218！
      expect(response.statusCode, equals(200));
      expect(response.data['status'], equals('ok'));
      expect(attemptsTo8219, equals(1));
      expect(attemptsTo8218, equals(1));
      expect(response.requestOptions.path, contains('8.218.176.238:3389'));
    });

    test('2. 【@Backend 驗收】subscribe_url 徹底剝離硬編碼主機、純路徑提取與 L2 金庫快取', () async {
      final customDio = Dio();
      customDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/api/v1/passport/auth/login')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'auth_data': 'JWT_AUTH_TOKEN_SAMPLE',
                      'token': 'MTgxODAyNDIx',
                    }
                  },
                ),
              );
            }
            if (options.path.contains('/api/v1/user/info')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'email': 'vip@tianhe.net',
                      'transfer_enable': 107374182400,
                      'u': 1000,
                      'd': 2000,
                    }
                  },
                ),
              );
            }
            if (options.path.contains('/api/v1/user/getSubscribe')) {
              // 模擬 V2Board 返回包含死 IP 8.219 的絕對網址
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'subscribe_url':
                          'https://8.219.196.216:8443/api/v1/client/subscribe?token=MTgxODAyNDIx',
                      'token': 'MTgxODAyNDIx',
                    }
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final client = DioClient(
        configService: configService,
        customDio: customDio,
      );

      final authManager = AuthManager(
        dioClient: client,
        storageService: storageService,
      );

      await authManager.login(email: 'vip@tianhe.net', password: 'pwd123456');
      final user = await authManager.fetchUserInfo();

      // 驗收 1：user.subscribeUrl 絕對不包含 8.219 硬編碼主機，只保留相對路徑與 Token！
      expect(user.subscribeUrl, isNot(contains('https://8.219.196.216:8443')));
      expect(user.subscribeUrl, equals('/api/v1/client/subscribe?token=MTgxODAyNDIx'));

      // 驗收 2：L2 加密金庫已儲存純相對路徑
      final cachedPath = await storageService.getCachedSubscribePath();
      expect(cachedPath, equals('/api/v1/client/subscribe?token=MTgxODAyNDIx'));

      // 驗收 3：原始主機被安全納入候選池末尾作為額外備援
      expect(configService.availableApiDomains, contains('https://8.219.196.216:8443'));
    });

    test('3. 【@DevOps 混沌容災實測】8.219 徹底掛掉時，觸發全備援併發競速搶答，秒切 8.218 獲取 36 顆節點並扶正主機', () async {
      // 設置候選主機：當前主機為掛掉的 8.219，備援主機包含 8.218:3389 與 8.218:8443
      final deadHost = 'https://8.219.196.216:8443';
      final liveHost = 'https://8.218.176.238:3389';
      final backupHost = 'https://8.218.176.238:8443';

      configService.setCurrentApiDomain(deadHost);
      configService.addCandidateDomain(liveHost);
      configService.addCandidateDomain(backupHost);

      expect(configService.currentApiDomain, equals(deadHost));

      final customDio = Dio();
      final stopwatch = Stopwatch()..start();

      customDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final uri = Uri.parse(options.path);
            if (uri.host == '8.219.196.216') {
              // 模擬 8.219 徹底斷網 / 拒絕連線
              return handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                  error: '8.219 is completely dead',
                ),
              );
            }

            if (uri.host == '8.218.176.238' && uri.port == 3389) {
              // 模擬 8.218:3389 正常且在 50ms 內快速搶答回傳 36 顆節點
              await Future.delayed(const Duration(milliseconds: 50));
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: generate36NodesYaml(),
                ),
              );
            }

            if (uri.host == '8.218.176.238' && uri.port == 8443) {
              // 模擬 8.218:8443 稍慢 (300ms)
              await Future.delayed(const Duration(milliseconds: 300));
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: generate36NodesYaml(),
                ),
              );
            }

            return handler.next(options);
          },
        ),
      );

      final client = DioClient(
        configService: configService,
        customDio: customDio,
      );

      final daemon = CoreDaemon();
      final engine = SubscriptionEngine(
        dioClient: client,
        coreDaemon: daemon,
        storageService: storageService,
        configService: configService,
      );

      // 觸發同步訂閱
      final nodes = await engine.syncSubscription(
        token: 'MTgxODAyNDIx',
        customSubscribeUrl: 'https://8.219.196.216:8443/api/v1/client/subscribe?token=MTgxODAyNDIx',
      );
      stopwatch.stop();

      // 驗收 1：成功拉回 36 顆節點
      expect(nodes.length, equals(36));
      expect(nodes.first.name, contains('香港 01'));
      expect(nodes.last.name, contains('新加坡 36'));

      // 驗收 2：勝出者 8.218:3389 被正式扶正為全域 currentApiDomain！死掉的 8.219 被拋棄！
      expect(configService.currentApiDomain, equals(liveHost));
      print('【混沌測試日誌】拉取 36 顆節點耗時: ${stopwatch.elapsedMilliseconds}ms，扶正後主機: ${configService.currentApiDomain}');

      // 驗收 3：再次同步時直接使用已扶正的 8.218:3389 走第一層極速直連通道
      final nodesSecondPass = await engine.syncSubscription(token: 'MTgxODAyNDIx');
      expect(nodesSecondPass.length, equals(36));
      expect(configService.currentApiDomain, equals(liveHost));
    });

    test('4. 【@Backend 驗收】前置 /api/v1/user/getSubscribe 異常時，使用 L2 金庫快取之相對路徑成功拉取節點', () async {
      // 事先在金庫快取專屬相對路徑與 Token
      await storageService.saveToken('VAULT_TOKEN_999');
      await storageService.saveCachedSubscribePath('/api/v1/client/subscribe?token=VAULT_TOKEN_999');

      final customDio = Dio();
      customDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // 訂閱下載端點回傳 36 顆節點
            if (options.path.contains('/api/v1/client/subscribe')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: generate36NodesYaml(),
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final client = DioClient(
        configService: configService,
        customDio: customDio,
      );

      final daemon = CoreDaemon();
      final engine = SubscriptionEngine(
        dioClient: client,
        coreDaemon: daemon,
        storageService: storageService,
        configService: configService,
      );

      // 在無 token 且未傳入 url 情況下手動同步，引擎應自動從金庫讀取快取路徑
      final nodes = await engine.performManualSync();
      expect(nodes.length, equals(36));
    });
  });
}
