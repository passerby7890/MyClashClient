// lib/business/subscription/config_generator.dart

import 'package:yaml/yaml.dart';
import '../../core/constants/app_constants.dart';
import 'node_model.dart';

/// Mihomo (Clash.Meta) 設定檔生成器
/// 將遠端節點資料整合轉換為符合核心規範之 YAML 設定檔
class ConfigGenerator {
  static final RegExp _whitespaceRegex = RegExp(r'[\r\n\t]+');

  /// 生成標準 Mihomo YAML 字串 (支援動態範本融合 Template Merging)
  /// [singleNodeSlice]: 單節點動態切片 (防 Root 扒節點，顯式啟用時僅切片當前選中節點，預設 false 保證全量相容)
  /// [templateYaml]: V2Board 下發之原始完整 default.clash.yaml 母體骨架 (若提供則 100% 繼承 DNS、策略組與自訂分流規則)
  static String generateYaml({
    required List<NodeModel> nodes,
    required String selectedNodeName,
    String routingMode = 'rule',
    int mixedPort = 7890,
    int controllerPort = 9090,
    String secret = AppConstants.coreSecret,
    String? controllerSecret,
    bool singleNodeSlice = false,
    String? templateYaml,
  }) {
    if (nodes.isEmpty) {
      throw ArgumentError('節點清單為空，無法生成核心設定檔');
    }

    // 1. 節點重名防護與名稱清理 (防止 Mihomo 解析 duplicate proxy 崩潰)
    final sanitizedNodes = <NodeModel>[];
    final seenNames = <String, int>{};
    for (final n in nodes) {
      String cleanName = n.name.replaceAll(_whitespaceRegex, ' ').trim();
      if (cleanName.isEmpty) cleanName = 'Node';
      String uniqueName = cleanName;
      if (seenNames.containsKey(cleanName)) {
        final count = seenNames[cleanName]! + 1;
        seenNames[cleanName] = count;
        uniqueName = '$cleanName #$count';
      } else {
        seenNames[cleanName] = 1;
      }
      if (uniqueName != n.name) {
        final newRaw = Map<String, dynamic>.from(n.internalRawConfig);
        newRaw['name'] = uniqueName;
        sanitizedNodes.add(NodeModel(
          id: n.id,
          name: uniqueName,
          flagEmoji: n.flagEmoji,
          protocol: n.protocol,
          latencyMs: n.latencyMs,
          rawConfig: newRaw,
        ));
      } else {
        sanitizedNodes.add(n);
      }
    }

    final allSanitizedNames = sanitizedNodes.map((n) => n.name).toList();
    final targetNode = sanitizedNodes.firstWhere(
      (n) => n.name.trim() == selectedNodeName.trim() || n.id == selectedNodeName,
      orElse: () => sanitizedNodes.first,
    );

    // 若啟用單節點動態切片 (Single-Node Slicing, 防 Root 扒節點)：
    // proxies 僅寫入當前選中之 1 顆節點，其餘未選中節點絕不寫入磁碟！
    final List<NodeModel> effectiveProxies = singleNodeSlice ? [targetNode] : sanitizedNodes;
    final effectiveProxyNames = effectiveProxies.map((n) => n.name).toList();
    final effectiveSelectedName = targetNode.name;

    // 2. 解析後端 templateYaml (若有提供)
    Map<String, dynamic>? templateDoc;
    if (templateYaml != null && templateYaml.trim().isNotEmpty) {
      try {
        final loaded = loadYaml(templateYaml);
        if (loaded is Map) {
          templateDoc = _deepCleanYaml(loaded) as Map<String, dynamic>;
        }
      } catch (e) {
        // ignore: avoid_print
        print('[ConfigGenerator] 範本 YAML 解析失敗，將使用高品質預設範本兜底: $e');
      }
    }

    final buffer = StringBuffer();

    // 3. 基礎設定 (Android 必備參數覆蓋注入)
    final validMode = ['rule', 'global', 'direct'].contains(routingMode.toLowerCase())
        ? routingMode.toLowerCase()
        : 'rule';

    buffer.writeln('# Tianhe Network Mihomo Configuration (Dynamic Template Merged)');
    buffer.writeln('mixed-port: $mixedPort');
    buffer.writeln('allow-lan: false');
    buffer.writeln('mode: $validMode');
    buffer.writeln('log-level: silent'); // 零明文原則：核心日誌靜音
    buffer.writeln('ipv6: false');
    buffer.writeln('external-controller: 127.0.0.1:$controllerPort');
    final effectiveSecret = controllerSecret ?? secret;
    buffer.writeln('secret: "$effectiveSecret"');
    buffer.writeln('geo-auto-update: false'); // 防 GitHub 連線更新卡死
    buffer.writeln('geodata-mode: false');
    buffer.writeln();

    // 4. TUN 虛擬網卡配置 (僅於 TUN 模式時啟用，避免 Windows 規則/全域模式因無管理員或缺 wintun.dll 崩潰)
    final bool isTun = routingMode.toLowerCase() == 'tun';
    buffer.writeln('tun:');
    buffer.writeln('  enable: $isTun');
    buffer.writeln('  stack: gvisor');
    buffer.writeln('  dns-hijack:');
    buffer.writeln('    - "any:53"');
    buffer.writeln('    - "tcp://any:53"');
    buffer.writeln('  auto-route: true');
    buffer.writeln('  auto-detect-interface: true');
    buffer.writeln();

    // 5. 域名嗅探機制 (Sniffer - 解決 App 寫死純 IP 繞過分流的痛點)
    buffer.writeln('sniffer:');
    buffer.writeln('  enable: true');
    buffer.writeln('  sniff:');
    buffer.writeln('    TLS:');
    buffer.writeln('      ports: [443, 8443]');
    buffer.writeln('    HTTP:');
    buffer.writeln('      ports: [80, 8080-8880]');
    buffer.writeln('  force-domain:');
    buffer.writeln('    - "+.netflix.com"');
    buffer.writeln('    - "+.spotify.com"');
    buffer.writeln('  skip-domain:');
    buffer.writeln('    - "Mijia Cloud"');
    buffer.writeln();

    // 6. DNS 設定 (100% 繼承後端 default-nameserver、proxy-server-nameserver 與 fallback-filter，拔除 "*")
    Map<String, dynamic> finalDns = {};
    if (templateDoc != null && templateDoc['dns'] is Map) {
      finalDns = Map<String, dynamic>.from(templateDoc['dns'] as Map);
    }

    finalDns['enable'] = true;
    finalDns['listen'] = '0.0.0.0:1053';
    finalDns['ipv6'] = false;
    finalDns['enhanced-mode'] = 'fake-ip';
    finalDns['fake-ip-range'] = '198.18.0.1/16';

    // 清洗 fake-ip-filter (徹底移除 "*" 避免 Fake-IP 全面失效)
    List<String> fakeIpFilters = [];
    if (finalDns['fake-ip-filter'] is List) {
      fakeIpFilters = (finalDns['fake-ip-filter'] as List)
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty && s != '*')
          .toList();
    }
    if (fakeIpFilters.isEmpty) {
      fakeIpFilters = [
        '*.lan',
        '+.local',
        '+.msftconnecttest.com',
        '+.msftncsi.com',
        'time.*.com',
        'ntp.*.com',
        '+.stun.*',
      ];
    }
    finalDns['fake-ip-filter'] = fakeIpFilters;

    // 確保關鍵 DNS 伺服器配置存在 (防節點伺服器域名解析死鎖)
    if (finalDns['default-nameserver'] == null || (finalDns['default-nameserver'] as List).isEmpty) {
      finalDns['default-nameserver'] = ['223.5.5.5', '119.29.29.29', '114.114.114.114'];
    }
    if (finalDns['proxy-server-nameserver'] == null || (finalDns['proxy-server-nameserver'] as List).isEmpty) {
      finalDns['proxy-server-nameserver'] = ['223.5.5.5', '119.29.29.29', '114.114.114.114'];
    }
    if (finalDns['nameserver'] == null || (finalDns['nameserver'] as List).isEmpty) {
      finalDns['nameserver'] = ['223.5.5.5', '119.29.29.29', '114.114.114.114'];
    }
    if (finalDns['fallback'] == null || (finalDns['fallback'] as List).isEmpty) {
      finalDns['fallback'] = ['1.1.1.1', '8.8.8.8'];
    }
    if (finalDns['fallback-filter'] == null) {
      finalDns['fallback-filter'] = {
        'geoip': true,
        'geoip-code': 'CN',
        'geosite': ['gfw'],
        'ipcidr': ['240.0.0.0/4'],
        'domain': ['+.google.com'],
      };
    }

    buffer.writeln('dns:');
    _writeYamlMap(buffer, finalDns, 2);
    buffer.writeln();

    // 7. 節點定義 (proxies - 單節點動態切片落地)
    buffer.writeln('proxies:');
    for (final node in effectiveProxies) {
      final config = Map<String, dynamic>.from(node.internalRawConfig);
      config['name'] = node.name;

      // ANYTLS / VLESS / Trojan 協定相容性消毒
      final protoLower = (config['type'] ?? node.protocol).toString().toLowerCase();
      config['type'] = protoLower;

      if (protoLower == 'anytls') {
        if (!config.containsKey('password') && config.containsKey('uuid')) {
          config['password'] = config['uuid'];
        }
        if (!config.containsKey('uuid') && config.containsKey('password')) {
          config['uuid'] = config['password'];
        }
      } else if (protoLower == 'vless') {
        if (!config.containsKey('uuid') && config.containsKey('password')) {
          config['uuid'] = config['password'];
        }
        if (!config.containsKey('network')) {
          config['network'] = 'tcp';
        }
      }

      // 布林值欄位強型別化 (避免被 quote 轉為字串引發 Mihomo YAML 解析異常)
      for (final boolKey in ['tls', 'udp', 'skip-cert-verify', 'xudp']) {
        if (config.containsKey(boolKey)) {
          final val = config[boolKey];
          if (val is String) {
            config[boolKey] = (val.toLowerCase() == 'true' || val == '1');
          } else if (val is num) {
            config[boolKey] = (val == 1);
          }
        }
      }

      // 數值欄位強型別化
      if (config.containsKey('port')) {
        final p = int.tryParse(config['port'].toString());
        if (p != null) config['port'] = p;
      }
      if (config.containsKey('alterId')) {
        final a = int.tryParse(config['alterId'].toString());
        if (a != null) config['alterId'] = a;
      }

      buffer.writeln('  - name: "${_escape(node.name)}"');
      config.forEach((k, v) {
        if (k == 'name' || v == null) return;
        if (v is Map) {
          buffer.writeln('    $k:');
          _writeYamlMap(buffer, v, 6);
        } else if (v is List) {
          buffer.writeln('    $k:');
          _writeYamlList(buffer, v, 6);
        } else if (v is String) {
          if (_shouldQuote(v)) {
            buffer.writeln('    $k: "${_escape(v)}"');
          } else {
            buffer.writeln('    $k: $v');
          }
        } else {
          buffer.writeln('    $k: $v');
        }
      });
    }
    buffer.writeln();

    // 8. 策略群組 (proxy-groups - 融合後端範本並清洗懸空節點，防 proxy not found 崩潰)
    final List<Map<String, dynamic>> finalProxyGroups = [];
    const specialKeywords = {'DIRECT', 'REJECT', 'PASS', 'COMPATIBLE', 'GLOBAL'};

    if (templateDoc != null && templateDoc['proxy-groups'] is List) {
      final rawGroups = (templateDoc['proxy-groups'] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final validGroupNames = rawGroups
          .map((g) => g['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();

      for (final rawGroup in rawGroups) {
        final groupName = rawGroup['name']?.toString() ?? '';
        if (groupName.isEmpty) continue;

        final groupMap = Map<String, dynamic>.from(rawGroup);
        final originalProxies = (groupMap['proxies'] as List?) ?? [];
        final newProxies = <String>{};

        for (final entry in originalProxies) {
          final str = entry.toString().trim();
          if (str.isEmpty) continue;

          // 若為其他策略組或特殊關鍵字，保留！
          if (validGroupNames.contains(str) || specialKeywords.contains(str.toUpperCase())) {
            newProxies.add(str);
          } else {
            // 若為具體伺服器節點名稱
            if (singleNodeSlice) {
              // 單節點切片：其餘 25 顆節點收斂替換為當前選中節點，杜絕 proxy not found！
              newProxies.add(effectiveSelectedName);
            } else {
              // 全量模式：在全量清單中則保留，若不在則替換為選中節點
              if (allSanitizedNames.contains(str)) {
                newProxies.add(str);
              } else {
                newProxies.add(effectiveSelectedName);
              }
            }
          }
        }

        // 防呆保底：若策略組為空，塞入選中節點
        if (newProxies.isEmpty) {
          newProxies.add(effectiveSelectedName);
        }

        groupMap['proxies'] = newProxies.toList();
        finalProxyGroups.add(groupMap);
      }
    }

    // 確保存在 PROXY 策略組
    if (!finalProxyGroups.any((g) => g['name'] == 'PROXY')) {
      finalProxyGroups.insert(0, {
        'name': 'PROXY',
        'type': 'select',
        'proxies': [
          effectiveSelectedName,
          if (!singleNodeSlice) ...effectiveProxyNames.where((n) => n != effectiveSelectedName),
          'DIRECT',
        ],
      });
    } else {
      // 確保 PROXY 策略組首位為有效選中節點
      final proxyGroup = finalProxyGroups.firstWhere((g) => g['name'] == 'PROXY');
      final list = (proxyGroup['proxies'] as List?)?.map((e) => e.toString()).toList() ?? [];
      list.remove(effectiveSelectedName);
      list.insert(0, effectiveSelectedName);
      proxyGroup['proxies'] = list;
    }

    // 確保存在 GLOBAL 策略組 (滿足 global 模式切換)
    if (!finalProxyGroups.any((g) => g['name'] == 'GLOBAL')) {
      finalProxyGroups.insert(1, {
        'name': 'GLOBAL',
        'type': 'select',
        'proxies': [
          'PROXY',
          effectiveSelectedName,
          if (!singleNodeSlice) ...effectiveProxyNames.where((n) => n != effectiveSelectedName),
          'DIRECT',
        ],
      });
    }

    buffer.writeln('proxy-groups:');
    for (final group in finalProxyGroups) {
      buffer.writeln('  - name: "${_escape(group['name'].toString())}"');
      group.forEach((k, v) {
        if (k == 'name' || v == null) return;
        if (v is Map) {
          buffer.writeln('    $k:');
          _writeYamlMap(buffer, v, 6);
        } else if (v is List) {
          buffer.writeln('    $k:');
          _writeYamlList(buffer, v, 6);
        } else if (v is String) {
          if (_shouldQuote(v)) {
            buffer.writeln('    $k: "${_escape(v)}"');
          } else {
            buffer.writeln('    $k: $v');
          }
        } else {
          buffer.writeln('    $k: $v');
        }
      });
    }
    buffer.writeln();

    // 9. 規則提供者 (rule-providers - 100% 完整繼承後端範本)
    if (templateDoc != null && templateDoc['rule-providers'] is Map) {
      buffer.writeln('rule-providers:');
      _writeYamlMap(buffer, templateDoc['rule-providers'] as Map, 2);
      buffer.writeln();
    }

    // 10. 分流規則集 (rules - 100% 完整繼承後端自訂 rules，無則使用高水準保底)
    List<String> finalRules = [];
    if (templateDoc != null && templateDoc['rules'] is List) {
      finalRules = (templateDoc['rules'] as List)
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (finalRules.isEmpty) {
      // 升級後的優質保底規則
      finalRules = [
        'DOMAIN-SUFFIX,local,DIRECT',
        'IP-CIDR,127.0.0.0/8,DIRECT',
        'IP-CIDR,172.16.0.0/12,DIRECT',
        'IP-CIDR,192.168.0.0/16,DIRECT',
        'IP-CIDR,10.0.0.0/8,DIRECT',
        'GEOIP,CN,DIRECT',
        'MATCH,PROXY',
      ];
    }

    buffer.writeln('rules:');
    for (final r in finalRules) {
      buffer.writeln('  - $r');
    }

    return buffer.toString();
  }

  /// 遞迴深度清理 YamlMap 與 YamlList，轉換為可修改之 Dart 原生 Map 與 List
  static dynamic _deepCleanYaml(dynamic yamlObject) {
    if (yamlObject is YamlMap || yamlObject is Map) {
      final map = <String, dynamic>{};
      yamlObject.forEach((k, v) {
        map[k.toString()] = _deepCleanYaml(v);
      });
      return map;
    } else if (yamlObject is YamlList || yamlObject is List) {
      return yamlObject.map((e) => _deepCleanYaml(e)).toList();
    }
    return yamlObject;
  }

  static void _writeYamlMap(StringBuffer buffer, Map map, int indent) {
    final pad = ' ' * indent;
    map.forEach((key, value) {
      if (value == null) return;
      if (value is Map) {
        buffer.writeln('$pad$key:');
        _writeYamlMap(buffer, value, indent + 2);
      } else if (value is List) {
        buffer.writeln('$pad$key:');
        _writeYamlList(buffer, value, indent + 2);
      } else if (value is String) {
        if (_shouldQuote(value)) {
          buffer.writeln('$pad$key: "${_escape(value)}"');
        } else {
          buffer.writeln('$pad$key: $value');
        }
      } else {
        buffer.writeln('$pad$key: $value');
      }
    });
  }

  static void _writeYamlList(StringBuffer buffer, List list, int indent) {
    final pad = ' ' * indent;
    for (final item in list) {
      if (item is Map) {
        buffer.writeln('$pad-');
        _writeYamlMap(buffer, item, indent + 2);
      } else if (item is String) {
        if (_shouldQuote(item)) {
          buffer.writeln('$pad- "${_escape(item)}"');
        } else {
          buffer.writeln('$pad- $item');
        }
      } else {
        buffer.writeln('$pad- $item');
      }
    }
  }

  static bool _shouldQuote(String str) {
    if (str.isEmpty) return true;
    if (str == 'true' || str == 'false' || str == 'null' || str == 'yes' || str == 'no') return true;
    const specialChars = [':', '{', '}', '[', ']', ',', '&', '*', '#', '?', '|', '-', '<', '>', '=', '!', '%', '@', '\\', '"', '\''];
    return specialChars.any((c) => str.contains(c)) || str.startsWith(' ') || str.endsWith(' ');
  }

  static String _escape(String str) {
    return str.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  /// 從傳入的 Clash/Mihomo YAML 字串中解析出節點清單 (具備髒資料過濾與重名消毒)
  static List<NodeModel> parseProxiesFromYaml(String yamlContent) {
    try {
      final doc = loadYaml(yamlContent);
      if (doc is! Map || doc['proxies'] is! List) {
        return [];
      }

      final proxiesList = doc['proxies'] as List;
      final result = <NodeModel>[];
      final seenNames = <String, int>{};

      for (int i = 0; i < proxiesList.length; i++) {
        final item = proxiesList[i];
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);

          // 1. 驗證是否為有效代理節點 (過濾無效 server/port/type 與公告卡片)
          if (!_isValidProxyMap(map)) continue;

          // 2. 清理名稱中異常控制字元
          String rawName = (map['name']?.toString() ?? 'Node').replaceAll(_whitespaceRegex, ' ').trim();
          if (rawName.isEmpty) rawName = 'Node_${i + 1}';

          // 3. 重名節點防護：為同名節點自動追加唯一後綴，避免核心衝突
          String uniqueName = rawName;
          if (seenNames.containsKey(rawName)) {
            final count = seenNames[rawName]! + 1;
            seenNames[rawName] = count;
            uniqueName = '$rawName #$count';
          } else {
            seenNames[rawName] = 1;
          }

          map['name'] = uniqueName;
          result.add(NodeModel.fromProxyMap(map, id: 'node_$i', sanitizedName: uniqueName));
        }
      }

      return result;
    } catch (e) {
      // ignore: avoid_print
      print('[ConfigGenerator] YAML 解析失敗: $e');
      return [];
    }
  }

  /// 檢查節點欄位是否具備連線基礎，並剔除非代理之公告卡片
  static bool _isValidProxyMap(Map map) {
    final server = map['server']?.toString().trim();
    if (server == null || server.isEmpty) return false;

    final portVal = map['port'];
    if (portVal == null) return false;
    final port = int.tryParse(portVal.toString());
    if (port == null || port <= 0 || port > 65535) return false;

    final type = map['type']?.toString().trim().toLowerCase();
    if (type == null || type.isEmpty || type == 'unknown') return false;

    // 過濾機場常見之純通知/到期提示卡片
    final name = map['name']?.toString() ?? '';
    const announcementKeywords = ['到期', '剩餘', '剩余', '流量', '官网', '官網', '通知', 'TG群', '公告', '频道', '頻道'];
    for (final kw in announcementKeywords) {
      if (name.contains(kw)) return false;
    }

    return true;
  }
}
