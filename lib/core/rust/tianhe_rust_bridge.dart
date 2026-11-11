// lib/core/rust/tianhe_rust_bridge.dart

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// C-ABI 函式型別簽名定義 (Raw C-ABI + dart:ffi)
typedef _TianheInitC = Bool Function();
typedef _TianheInitDart = bool Function();

typedef _TianheFreeStringC = Void Function(Pointer<Utf8>);
typedef _TianheFreeStringDart = void Function(Pointer<Utf8>);

typedef _TianheVersionC = Pointer<Utf8> Function();
typedef _TianheVersionDart = Pointer<Utf8> Function();

typedef _TianheStrToStrC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _TianheStrToStrDart = Pointer<Utf8> Function(Pointer<Utf8>);

typedef _TianheNoArgToStrC = Pointer<Utf8> Function();
typedef _TianheNoArgToStrDart = Pointer<Utf8> Function();

typedef _TianheRaceAndVaultC = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _TianheRaceAndVaultDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _TianhePrepareL0C = Bool Function(UintPtr, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _TianhePrepareL0Dart = bool Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);

typedef _TianheSelectNodeC = Bool Function(UintPtr, Pointer<Utf8>, Pointer<Utf8>);
typedef _TianheSelectNodeDart = bool Function(int, Pointer<Utf8>, Pointer<Utf8>);

typedef _TianheBatchPingC = Pointer<Utf8> Function(Uint64);
typedef _TianheBatchPingDart = Pointer<Utf8> Function(int);

typedef _TianheCancelPingC = Void Function();
typedef _TianheCancelPingDart = void Function();

typedef _TianheSetProxyC = Bool Function(Bool, Uint16);
typedef _TianheSetProxyDart = bool Function(bool, int);

typedef _TianheAssignPidC = Bool Function(Uint32);
typedef _TianheAssignPidDart = bool Function(int);

typedef _TianheBoolPathC = Bool Function(Pointer<Utf8>);
typedef _TianheBoolPathDart = bool Function(Pointer<Utf8>);

/// Rust 原生安全與高速引擎 (libtianhe_rust v3.4.0) 雙軌橋接器
///
/// 特色：
/// 1. 雙軌平滑保護：若原生動態庫存在則啟用 Rust 硬核加速；不存在則無痛降級回 Dart 邏輯。
/// 2. 0 記憶體洩漏 (Mandatory Fix 5)：所有 C 字串回傳指標均強制於 `try ... finally` 呼叫 `tianhe_free_string` 釋放。
/// 3. 120Hz 零卡頓：所有網路競速、加解密、YAML 解析與高併發測速均強制透過 `Isolate.run` 在背景執行。
class TianheRustBridge {
  TianheRustBridge._();
  static final TianheRustBridge instance = TianheRustBridge._();

  String? _resolvedLibPath;
  DynamicLibrary? _mainLib;
  bool _initialized = false;

  bool get isAvailable => _initialized && _mainLib != null && _resolvedLibPath != null;

  /// 解析跨平台動態庫實體路徑
  static String? resolveLibraryPath() {
    if (kIsWeb) return null;

    final String libFileName;
    if (Platform.isWindows) {
      libFileName = 'tianhe_rust.dll';
    } else if (Platform.isMacOS) {
      libFileName = 'libtianhe_rust.dylib';
    } else if (Platform.isAndroid || Platform.isLinux) {
      libFileName = 'libtianhe_rust.so';
    } else {
      return null;
    }

    final candidates = <String>[
      // 1. 隨發行可執行檔旁 (Windows Portable / macOS Frameworks)
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$libFileName',
      if (Platform.isMacOS)
        '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/$libFileName',
      // 2. 當前工作目錄或本地打包目錄
      '${Directory.current.path}${Platform.pathSeparator}$libFileName',
      '${Directory.current.path}${Platform.pathSeparator}rust_core${Platform.pathSeparator}target${Platform.pathSeparator}release${Platform.pathSeparator}$libFileName',
      '${Directory.current.path}${Platform.pathSeparator}rust_core${Platform.pathSeparator}target${Platform.pathSeparator}debug${Platform.pathSeparator}$libFileName',
      // 3. Android 系統 jniLibs 搜尋路徑名稱
      libFileName,
    ];

    for (final path in candidates) {
      if (path == libFileName) {
        return path; // 交由作業系統系統路徑 (dlopen) 嘗試載入
      }
      if (File(path).existsSync()) {
        return path;
      }
    }
    return libFileName;
  }

  /// 初始化 Rust 引擎並啟動 Tokio Runtime 與進程守護
  bool init() {
    if (_initialized) return isAvailable;
    if (kIsWeb) return false;

    final libPath = resolveLibraryPath();
    if (libPath == null) return false;

    try {
      final lib = DynamicLibrary.open(libPath);
      final initFn = lib.lookupFunction<_TianheInitC, _TianheInitDart>('tianhe_init');
      final ok = initFn();
      if (ok) {
        _resolvedLibPath = libPath;
        _mainLib = lib;
        _initialized = true;
        return true;
      }
    } catch (_) {
      // 動態庫未打包或載入失敗時，自動降級回純 Dart 雙軌邏輯，不影響 App 正常運行
      _initialized = false;
      _mainLib = null;
      _resolvedLibPath = null;
    }
    return false;
  }

  /// 讀取引擎版本 (同步快速讀取)
  String? getEngineVersion() {
    if (!isAvailable) return null;
    final lib = _mainLib!;
    final verFn = lib.lookupFunction<_TianheVersionC, _TianheVersionDart>('tianhe_engine_version');
    final freeFn = lib.lookupFunction<_TianheFreeStringC, _TianheFreeStringDart>('tianhe_free_string');
    final ptr = verFn();
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      freeFn(ptr);
    }
  }

  /// Worker Isolate 安全執行器：讀寫完指標後強制釋放 Rust 字串避免 Memory Leak
  static String _readAndFreeRustString(DynamicLibrary lib, Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      throw Exception('Rust FFI returned null pointer');
    }
    final freeFn = lib.lookupFunction<_TianheFreeStringC, _TianheFreeStringDart>('tianhe_free_string');
    try {
      return ptr.toDartString();
    } finally {
      freeFn(ptr);
    }
  }

  /// 1. [VaultCrypto] AES-256-CBC 解密 (透過 Isolate.run 執行防卡頓)
  Future<String?> decryptConfig(String ciphertext) async {
    if (!init()) return null;
    final libPath = _resolvedLibPath!;

    try {
      final rawJson = await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheStrToStrC, _TianheStrToStrDart>('tianhe_decrypt_config');
        final argPtr = ciphertext.toNativeUtf8();
        try {
          final resPtr = fn(argPtr);
          return _readAndFreeRustString(lib, resPtr);
        } finally {
          calloc.free(argPtr);
        }
      });

      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        return decoded['data']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 2. [VaultCrypto] AES-256-CBC 加密 (供測試或設定檔產生使用)
  Future<String?> encryptConfig(String plaintext) async {
    if (!init()) return null;
    final libPath = _resolvedLibPath!;

    try {
      final rawJson = await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheStrToStrC, _TianheStrToStrDart>('tianhe_encrypt_config');
        final argPtr = plaintext.toNativeUtf8();
        try {
          final resPtr = fn(argPtr);
          return _readAndFreeRustString(lib, resPtr);
        } finally {
          calloc.free(argPtr);
        }
      });

      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        return decoded['data']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 3. [NetRacer + VaultCrypto] 全網多級 DoH + 阿里雲 OSS 並行競速取得遠端設定 JSON
  Future<Map<String, dynamic>?> resolveRemoteConfig() async {
    if (!init()) return null;
    final libPath = _resolvedLibPath!;

    try {
      final rawJson = await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheNoArgToStrC, _TianheNoArgToStrDart>('tianhe_resolve_remote_config');
        final resPtr = fn();
        return _readAndFreeRustString(lib, resPtr);
      });

      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      if (decoded['ok'] == true && decoded['data'] is String) {
        return json.decode(decoded['data'] as String) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 4. [NetRacer + YamlEngine] Happy Eyeballs 2.5s 並發競速下載訂閱 + 鎖死在 Rust 記憶體金庫
  /// 僅回傳 SafeNodeDescriptor 清單、加密快取密文與勝出主機，UI 層徹底 0 IP/UUID/密碼 洩漏！
  Future<({String winnerHost, List<Map<String, dynamic>> nodes, String encryptedBackup})?> raceAndVaultSubscription({
    required List<String> hosts,
    required String relativePath,
  }) async {
    if (!init()) return null;
    final libPath = _resolvedLibPath!;
    final hostsJsonStr = json.encode(hosts);

    try {
      final rawJson = await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheRaceAndVaultC, _TianheRaceAndVaultDart>(
          'tianhe_race_and_vault_subscription',
        );
        final hostsPtr = hostsJsonStr.toNativeUtf8();
        final pathPtr = relativePath.toNativeUtf8();
        try {
          final resPtr = fn(hostsPtr, pathPtr);
          return _readAndFreeRustString(lib, resPtr);
        } finally {
          calloc.free(hostsPtr);
          calloc.free(pathPtr);
        }
      });

      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      if (decoded['ok'] == true && decoded['data'] is Map) {
        final data = decoded['data'] as Map<String, dynamic>;
        final winner = data['winner_host']?.toString() ?? '';
        final encryptedBackup = data['encrypted_backup']?.toString() ?? '';
        final rawNodes = (data['nodes'] as List?) ?? [];
        final safeNodes = rawNodes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        return (winnerHost: winner, nodes: safeNodes, encryptedBackup: encryptedBackup);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 5. [YamlEngine] 解析原始 YAML 並鎖入 Rust 金庫，回傳安全節點描述符清單
  Future<List<Map<String, dynamic>>?> parseYamlToVault(String rawYaml) async {
    if (!init()) return null;
    final libPath = _resolvedLibPath!;

    try {
      final rawJson = await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheStrToStrC, _TianheStrToStrDart>('tianhe_parse_yaml');
        final yamlPtr = rawYaml.toNativeUtf8();
        try {
          final resPtr = fn(yamlPtr);
          return _readAndFreeRustString(lib, resPtr);
        } finally {
          calloc.free(yamlPtr);
        }
      });

      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      if (decoded['ok'] == true && decoded['data'] is List) {
        return (decoded['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 6. [YamlEngine] 冷啟動準備 L0 設定檔至私密路徑 (支援 fullPool 全節點池與 single slice 雙模式)
  Future<bool> prepareL0Config({
    required int nodeId,
    required String routingMode,
    required String outputPath,
    required String secret,
    bool fullPool = false,
  }) async {
    if (!init()) return false;
    final libPath = _resolvedLibPath!;
    final symbolName = fullPool ? 'tianhe_prepare_l0_pool_config' : 'tianhe_prepare_l0_config';

    try {
      return await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianhePrepareL0C, _TianhePrepareL0Dart>(symbolName);
        final modePtr = routingMode.toNativeUtf8();
        final pathPtr = outputPath.toNativeUtf8();
        final secretPtr = secret.toNativeUtf8();
        try {
          return fn(nodeId, modePtr, pathPtr, secretPtr);
        } finally {
          calloc.free(modePtr);
          calloc.free(pathPtr);
          calloc.free(secretPtr);
        }
      });
    } catch (_) {
      return false;
    }
  }

  /// 6b. [YamlEngine] 取得母體範本中所有可供指標熱切換的 select 策略組名稱
  Future<List<String>> getSelectGroupNames() async {
    if (!init()) return const ['PROXY', 'GLOBAL'];
    final libPath = _resolvedLibPath!;

    try {
      final rawJson = await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheNoArgToStrC, _TianheNoArgToStrDart>('tianhe_get_select_groups');
        final resPtr = fn();
        return _readAndFreeRustString(lib, resPtr);
      });

      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      if (decoded['ok'] == true && decoded['data'] is List) {
        return (decoded['data'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return const ['PROXY', 'GLOBAL'];
  }

  /// 7. [YamlEngine] 閱後即焚：覆寫歸零並刪除臨時設定檔
  Future<bool> shredFile(String path) async {
    if (!init()) return false;
    final libPath = _resolvedLibPath!;

    try {
      return await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheBoolPathC, _TianheBoolPathDart>('tianhe_shred_file');
        final pathPtr = path.toNativeUtf8();
        try {
          return fn(pathPtr);
        } finally {
          calloc.free(pathPtr);
        }
      });
    } catch (_) {
      return false;
    }
  }

  /// 8. [YamlEngine] 連線中瞬切節點：直推 9090 端口 + 切斷舊連線 (Mandatory Fix 4)
  Future<bool> selectNodeAndApply({
    required int nodeId,
    required String routingMode,
    required String secret,
  }) async {
    if (!init()) return false;
    final libPath = _resolvedLibPath!;

    try {
      return await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheSelectNodeC, _TianheSelectNodeDart>('tianhe_select_node');
        final modePtr = routingMode.toNativeUtf8();
        final secretPtr = secret.toNativeUtf8();
        try {
          return fn(nodeId, modePtr, secretPtr);
        } finally {
          calloc.free(modePtr);
          calloc.free(secretPtr);
        }
      });
    } catch (_) {
      return false;
    }
  }

  /// 9. [PingEngine] Tokio 50 路並發微秒級測速 (Mandatory Fix 2: 零 IP 參數洩漏)
  Future<List<({int id, int latency})>?> batchPingVaultNodes({int timeoutMs = 1500}) async {
    if (!init()) return null;
    final libPath = _resolvedLibPath!;

    try {
      final rawJson = await Isolate.run(() {
        final lib = DynamicLibrary.open(libPath);
        final fn = lib.lookupFunction<_TianheBatchPingC, _TianheBatchPingDart>('tianhe_batch_ping');
        final resPtr = fn(timeoutMs);
        return _readAndFreeRustString(lib, resPtr);
      });

      final decoded = json.decode(rawJson) as Map<String, dynamic>;
      if (decoded['ok'] == true && decoded['data'] is List) {
        final list = decoded['data'] as List;
        return list.map((item) {
          final m = item as Map;
          return (
            id: (m['id'] as num).toInt(),
            latency: (m['latency'] as num).toInt(),
          );
        }).toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 10. [PingEngine] 原子操作一鍵立即中止測速
  void cancelPing() {
    if (!isAvailable) return;
    try {
      final fn = _mainLib!.lookupFunction<_TianheCancelPingC, _TianheCancelPingDart>('tianhe_cancel_ping');
      fn();
    } catch (_) {}
  }

  /// 11. [SysGuardian] 原生系統代理秒切 (< 1ms)
  bool setSystemProxy(bool enable, {int port = 7890}) {
    if (!init()) return false;
    try {
      final fn = _mainLib!.lookupFunction<_TianheSetProxyC, _TianheSetProxyDart>('tianhe_set_system_proxy');
      return fn(enable, port);
    } catch (_) {
      return false;
    }
  }

  /// 12. [SysGuardian] 將子進程 PID 綁定至 Windows Job Object (殺主殺子防殭屍)
  bool assignJobPid(int pid) {
    if (!init()) return false;
    try {
      final fn = _mainLib!.lookupFunction<_TianheAssignPidC, _TianheAssignPidDart>('tianhe_assign_job_pid');
      return fn(pid);
    } catch (_) {
      return false;
    }
  }
}
