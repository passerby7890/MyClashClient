// test/e2e_simulation_test.dart

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/auth/auth_manager.dart';
import 'package:flclash_v2board_client/business/shop/shop_manager.dart';
import 'package:flclash_v2board_client/business/subscription/config_generator.dart';
import 'package:flclash_v2board_client/business/subscription/subscription_engine.dart';
import 'package:flclash_v2board_client/core/network/auth_interceptor.dart';
import 'package:flclash_v2board_client/core/network/dio_client.dart';
import 'package:flclash_v2board_client/core/storage/secure_storage_service.dart';
import 'package:flclash_v2board_client/infrastructure/config/app_config_service.dart';
import 'package:flclash_v2board_client/infrastructure/core_daemon/core_daemon.dart';

/// 模擬記憶體 Secure Storage，供單元/端到端測試使用
class MockMemorySecureStorage extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> saveToken(String token) async {
    _data['v2board_jwt_token'] = token;
  }

  @override
  Future<String?> getToken() async {
    return _data['v2board_jwt_token'];
  }

  @override
  Future<void> saveUserInfoJson(String jsonStr) async {
    _data['v2board_user_info'] = jsonStr;
  }

  @override
  Future<String?> getUserInfoJson() async {
    return _data['v2board_user_info'];
  }

  @override
  Future<void> clearAll() async {
    _data.clear();
  }
}

void main() {
  group('全功能模擬整合測試 (端到端 API 串接與連線隧道驗證)', () {
    late Dio mockDio;
    late DioClient dioClient;
    late MockMemorySecureStorage storage;
    late AuthManager authManager;
    late CoreDaemon coreDaemon;
    late SubscriptionEngine subscriptionEngine;
    late ShopManager shopManager;

    setUp(() {
      mockDio = Dio(BaseOptions(baseUrl: 'https://0n21.com'));
      storage = MockMemorySecureStorage();

      final configService = AppConfigService();
      dioClient = DioClient(configService: configService, customDio: mockDio);

      authManager = AuthManager(
        dioClient: dioClient,
        storageService: storage,
      );

      final authInterceptor = AuthInterceptor(
        storageService: storage,
        onUnauthorized: () => authManager.handleUnauthorized(),
      );
      dioClient.addInterceptor(authInterceptor);

      coreDaemon = CoreDaemon();

      // 套用與 DashboardScreen 相同的共享 authenticated dioClient
      subscriptionEngine = SubscriptionEngine(
        dioClient: authManager.dioClient,
        coreDaemon: coreDaemon,
        storageService: storage,
      );

      shopManager = ShopManager(dioClient: authManager.dioClient);

      // 安裝 Dio Mock 攔截器以模擬 V2Board 後台真實 API 回應
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            final authHeader = options.headers['Authorization'];

            // 1. 登入端點
            if (path.contains('/api/v1/passport/auth/login')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'token': 'mock_jwt_token_abcdef123456',
                      'auth_data': 'mock_jwt_token_abcdef123456',
                    }
                  },
                ),
              );
            }

            // 2. 其餘端點均需檢驗 Token (非公開端點若無 Authorization 則模擬後端 401)
            if (authHeader == null || authHeader.isEmpty) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {'message': '未登录或登陆已过期'},
                  ),
                ),
              );
            }

            // 3. 用戶資訊端點
            if (path.contains('/api/v1/user/info')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'email': 'vip_user@example.com',
                      'transfer_enable': 3758096384000, // 3500 GB
                      'u': 25628696576, // 23.87 GB
                      'd': 0,
                      'expired_at': 1791791854,
                      'plan_id': 3,
                      'balance': 5000,
                      'commission_balance': 12000,
                      'token': 'sub_token_xyz987',
                    }
                  },
                ),
              );
            }

            // 4. 套餐列表端點
            if (path.contains('/api/v1/user/plan/fetch')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'id': 3,
                        'name': '专业套餐',
                        'transfer_enable': 3500,
                        'month_price': 9800,
                        'year_price': 85800,
                        'content': '[{"feature":"每月 3500G 流量，6折重置","support":true},{"feature":"全球51个节点接入","support":true}]',
                        'show': 1,
                      },
                      {
                        'id': 5,
                        'name': '天河尊享專線套餐',
                        'transfer_enable': 5000,
                        'month_price': 15800,
                        'year_price': 138000,
                        'content': '[{"feature":"高速专线低延迟","support":true},{"feature":"全平台客户端支持","support":true}]',
                        'show': 1,
                      }
                    ]
                  },
                ),
              );
            }

            // 5. 支付方式端點
            if (path.contains('/api/v1/user/order/getPaymentMethod')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {'id': 1, 'name': '微信支付', 'payment': 'WeChat'},
                      {'id': 2, 'name': '支付宝', 'payment': 'Alipay'},
                      {'id': 3, 'name': 'USDT-TRC20', 'payment': 'Crypto'},
                    ]
                  },
                ),
              );
            }

            // 6. 建立訂單端點
            if (path.contains('/api/v1/user/order/save')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': '20261012170024987654321'},
                ),
              );
            }

            // 7. 歷史訂單端點
            if (path.contains('/api/v1/user/order/fetch')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': [
                      {
                        'trade_no': '20261012170024987654321',
                        'plan_id': 3,
                        'total_amount': 9800,
                        'status': 0,
                        'created_at': 1791791854,
                        'plan': {'id': 3, 'name': '专业套餐'},
                      }
                    ]
                  },
                ),
              );
            }

            // 8. 訂閱端點 (返回 Clash YAML)
            if (path.contains('/api/v1/client/subscribe')) {
              const mockClashYaml = '''
proxies:
  - name: "🇭🇰 香港 01 [專線]"
    type: trojan
    server: hk01.node.example.com
    port: 443
    password: mock_secret_pass_1
    udp: true
    sni: hk01.node.example.com
  - name: "🇯🇵 日本 01 [BGP]"
    type: vmess
    server: jp01.node.example.com
    port: 443
    uuid: 87654321-4321-4321-4321-210987654321
    alterId: 0
    cipher: auto
    tls: true
  - name: "🇺🇸 美國 01 [原生]"
    type: ss
    server: us01.node.example.com
    port: 8388
    cipher: aes-256-gcm
    password: mock_ss_password_1
''';
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: mockClashYaml,
                ),
              );
            }

            return handler.next(options);
          },
        ),
      );
    });

    test('1. 完整認證登入流程：Token 保存與自動注入驗證', () async {
      // 1. 執行登入
      final user = await authManager.login(
        email: 'vip_user@example.com',
        password: 'password123',
      );

      expect(authManager.state.isAuthenticated, isTrue);
      expect(user.email, equals('vip_user@example.com'));
      expect(authManager.state.token, equals('mock_jwt_token_abcdef123456'));

      // 2. 驗證 Storage 中已保存 Token
      final savedToken = await storage.getToken();
      expect(savedToken, equals('mock_jwt_token_abcdef123456'));
    });

    test('2. 登入後套餐商城與支付方式 API 串接完整性驗證 (解決資料空白問題)', () async {
      // 模擬登入完成狀態
      await authManager.login(email: 'vip_user@example.com', password: 'password123');

      // 1. 獲取套餐列表
      final plans = await shopManager.fetchPlans();
      expect(plans, isNotEmpty);
      expect(plans.length, equals(2));
      expect(plans[0].name, equals('专业套餐'));
      expect(plans[0].displayPrice, equals(98.0));
      expect(plans[1].name, equals('天河尊享專線套餐'));
      expect(plans[1].displayPrice, equals(158.0));

      // 2. 獲取支付方式
      final paymentMethods = await shopManager.fetchPaymentMethods();
      expect(paymentMethods.length, equals(3));
      expect(paymentMethods[0].name, equals('微信支付'));
      expect(paymentMethods[1].name, equals('支付宝'));

      // 3. 建立購買訂單
      final tradeNo = await shopManager.createOrder(planId: 3, period: 'month_price');
      expect(tradeNo, equals('20261012170024987654321'));

      // 4. 獲取歷史訂單列表
      final orders = await shopManager.fetchOrders();
      expect(orders.length, equals(1));
      expect(orders[0].tradeNo, equals('20261012170024987654321'));
      expect(orders[0].planName, equals('专业套餐'));
    });

    test('3. 訂閱拉取、節點解析與 Mihomo 靜默設定檔生成驗證', () async {
      await authManager.login(email: 'vip_user@example.com', password: 'password123');

      // 1. 靜默同步訂閱
      final nodes = await subscriptionEngine.syncSubscription(
        token: authManager.state.token!,
      );

      expect(nodes.length, equals(3));
      expect(nodes[0].name, equals('🇭🇰 香港 01 [專線]'));
      expect(nodes[0].flagEmoji, equals('🇭🇰'));
      expect(nodes[0].protocol, equals('TROJAN'));
      expect(nodes[1].name, equals('🇯🇵 日本 01 [BGP]'));
      expect(nodes[1].flagEmoji, equals('🇯🇵'));
      expect(nodes[1].protocol, equals('VMESS'));
      expect(nodes[2].name, equals('🇺🇸 美國 01 [原生]'));
      expect(nodes[2].flagEmoji, equals('🇺🇸'));
      expect(nodes[2].protocol, equals('SS'));

      // 2. 驗證選定節點
      expect(subscriptionEngine.selectedNode, isNotNull);
      expect(subscriptionEngine.selectedNode!.name, equals('🇭🇰 香港 01 [專線]'));

      // 3. 生成 Mihomo YAML 設定檔
      final generatedYaml = ConfigGenerator.generateYaml(
        nodes: nodes,
        selectedNodeName: subscriptionEngine.selectedNode!.name,
      );

      expect(generatedYaml, contains('mixed-port: 7890'));
      expect(generatedYaml, contains('fake-ip'));
      expect(generatedYaml, contains('🇭🇰 香港 01 [專線]'));
      expect(generatedYaml, contains('PROXY'));
      expect(generatedYaml, contains('GLOBAL'));
    });

    test('4. 節點切換與核心守護連線生命週期模擬測試', () async {
      await authManager.login(email: 'vip_user@example.com', password: 'password123');
      final nodes = await subscriptionEngine.syncSubscription(token: authManager.state.token!);

      // 切換至日本節點
      final jpNode = nodes[1];
      await subscriptionEngine.selectNode(jpNode);
      expect(subscriptionEngine.selectedNode!.name, equals('🇯🇵 日本 01 [BGP]'));

      // 啟動連線 (模擬)
      await coreDaemon.start(
        configPath: '/mock/config.yaml',
        selectedNode: jpNode.name,
      );

      expect(coreDaemon.state.isConnected, isTrue);
      expect(coreDaemon.state.activeNodeName, equals('🇯🇵 日本 01 [BGP]'));

      // 斷開連線
      await coreDaemon.stop();
      expect(coreDaemon.state.isDisconnected, isTrue);
    });
  });
}
