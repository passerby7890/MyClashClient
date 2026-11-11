// rust_core/src/yaml_engine/mod.rs
use crate::vault_crypto::VaultCrypto;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use lazy_static::lazy_static;
use obfstr::obfstr;
use serde::{Deserialize, Serialize};
use serde_yaml::{Mapping, Value};
use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::sync::RwLock;

lazy_static! {
    /// 🔒 節點機密金庫：36+ 顆真實節點資料（含原生 IP、Port、UUID、Password）
    /// 100% 封鎖在 Rust 靜態記憶體中，絕不向 Dart/UI 層暴露！
    pub static ref VAULT_PROXIES: RwLock<Vec<Value>> = RwLock::new(Vec::new());

    /// 🔒 V2Board 原始分流範本母體（包含 dns, rules, rule-providers, proxy-groups, sniffer 等）
    pub static ref VAULT_BASE_TEMPLATE: RwLock<Option<Value>> = RwLock::new(None);
}

/// UI 專用安全節點描述符 (100% 零機密)
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct SafeNodeDescriptor {
    pub id: usize,
    pub name: String,
    pub protocol: String,
    pub country_code: String,
}

pub struct YamlEngine;

impl YamlEngine {
    /// 解析 V2Board 下發之訂閱字串 (支援 Base64、RUST_ENC AES密文自動解碼或原始 YAML)
    /// 將真實節點與規則母體鎖入 Rust 靜態金庫，僅回傳安全描述符清單給 Dart
    pub fn parse_and_vault(raw_content: &str) -> Result<Vec<SafeNodeDescriptor>, String> {
        let trimmed_initial = raw_content.trim();
        let decrypted_owned;
        let content_trimmed = if let Some(cipher) = trimmed_initial.strip_prefix("RUST_ENC:") {
            decrypted_owned = VaultCrypto::decrypt_cbc(cipher)?;
            decrypted_owned.trim()
        } else {
            trimmed_initial
        };

        let yaml_str = if !content_trimmed.contains("proxies:") && !content_trimmed.contains("proxy-groups:") {
            match BASE64.decode(content_trimmed.replace(['\n', '\r', ' '], "")) {
                Ok(bytes) => String::from_utf8(bytes).unwrap_or_else(|_| content_trimmed.to_string()),
                Err(_) => content_trimmed.to_string(),
            }
        } else {
            content_trimmed.to_string()
        };

        let root: Value = serde_yaml::from_str(&yaml_str)
            .map_err(|e| format!("YAML 解析失敗: {}", e))?;

        let proxies_seq = root.get("proxies")
            .and_then(|p| p.as_sequence())
            .ok_or_else(|| "YAML 未包含有效的 'proxies' 節點陣列".to_string())?;

        let mut sanitized_proxies = Vec::new();
        let mut descriptors = Vec::new();
        let mut seen_names: HashMap<String, usize> = HashMap::new();

        for proxy in proxies_seq {
            let mut proxy_map = match proxy.as_mapping() {
                Some(m) => m.clone(),
                None => continue,
            };

            let raw_name = proxy_map.get(&Value::String("name".to_string()))
                .and_then(|v| v.as_str())
                .unwrap_or("Node")
                .replace(['\r', '\n', '\t'], " ")
                .trim()
                .to_string();
            let clean_name = if raw_name.is_empty() { "Node".to_string() } else { raw_name };

            // 過濾髒訂閱提示資訊節點
            let lower_name = clean_name.to_lowercase();
            if lower_name.contains("剩餘流量") || lower_name.contains("剩余流量") || lower_name.contains("過期時間") || lower_name.contains("过期时间") || lower_name.contains("官網") || lower_name.contains("官网") {
                continue;
            }

            // 重名防護與消毒 (例如 "香港 01" -> "香港 01 #2")
            let count = seen_names.entry(clean_name.clone()).or_insert(0);
            *count += 1;
            let unique_name = if *count > 1 {
                format!("{} #{}", clean_name, *count)
            } else {
                clean_name
            };

            // 更新節點名稱
            proxy_map.insert(
                Value::String("name".to_string()),
                Value::String(unique_name.clone()),
            );

            // 協議相容性消毒 (ANYTLS / VLESS 強型別防呆)
            let proto_raw = proxy_map.get(&Value::String("type".to_string()))
                .and_then(|v| v.as_str())
                .unwrap_or("UNKNOWN")
                .trim()
                .to_lowercase();
            proxy_map.insert(Value::String("type".to_string()), Value::String(proto_raw.clone()));

            if proto_raw == "anytls" {
                let uuid_val = proxy_map.get(&Value::String("uuid".to_string())).cloned();
                let pass_val = proxy_map.get(&Value::String("password".to_string())).cloned();
                if pass_val.is_none() {
                    if let Some(u) = uuid_val {
                        proxy_map.insert(Value::String("password".to_string()), u);
                    }
                } else if uuid_val.is_none() {
                    if let Some(p) = pass_val {
                        proxy_map.insert(Value::String("uuid".to_string()), p);
                    }
                }
            } else if proto_raw == "vless" {
                if !proxy_map.contains_key(&Value::String("uuid".to_string())) {
                    if let Some(p) = proxy_map.get(&Value::String("password".to_string())).cloned() {
                        proxy_map.insert(Value::String("uuid".to_string()), p);
                    }
                }
                if !proxy_map.contains_key(&Value::String("network".to_string())) {
                    proxy_map.insert(Value::String("network".to_string()), Value::String("tcp".to_string()));
                }
            }

            let country = Self::extract_country_code(&unique_name);
            let id = descriptors.len();

            descriptors.push(SafeNodeDescriptor {
                id,
                name: unique_name,
                protocol: proto_raw.to_uppercase(),
                country_code: country,
            });

            sanitized_proxies.push(Value::Mapping(proxy_map));
        }

        if sanitized_proxies.is_empty() {
            return Err("未解析出任何有效代理節點".to_string());
        }

        // 鎖入 Rust 私有金庫
        {
            let mut vault_p = VAULT_PROXIES.write().unwrap();
            *vault_p = sanitized_proxies;
        }
        {
            let mut vault_t = VAULT_BASE_TEMPLATE.write().unwrap();
            *vault_t = Some(root);
        }

        Ok(descriptors)
    }

    /// 根據節點名稱智慧提取國家/地區 ISO 代碼
    pub fn extract_country_code(name: &str) -> String {
        let upper = name.to_uppercase();
        if upper.contains("香港") || upper.contains("HK") || upper.contains("HONG KONG") {
            "HK".to_string()
        } else if upper.contains("日本") || upper.contains("JP") || upper.contains("JAPAN") || upper.contains("东京") || upper.contains("大阪") {
            "JP".to_string()
        } else if upper.contains("美國") || upper.contains("美国") || upper.contains("US") || upper.contains("USA") || upper.contains("洛杉矶") || upper.contains("硅谷") {
            "US".to_string()
        } else if upper.contains("新加坡") || upper.contains("SG") || upper.contains("SINGAPORE") || upper.contains("狮城") {
            "SG".to_string()
        } else if upper.contains("台灣") || upper.contains("台湾") || upper.contains("TW") || upper.contains("TAIWAN") || upper.contains("台北") {
            "TW".to_string()
        } else if upper.contains("韓國") || upper.contains("韩国") || upper.contains("KR") || upper.contains("KOREA") || upper.contains("首尔") {
            "KR".to_string()
        } else if upper.contains("英國") || upper.contains("英国") || upper.contains("UK") || upper.contains("GB") || upper.contains("伦敦") {
            "GB".to_string()
        } else if upper.contains("德國") || upper.contains("德国") || upper.contains("DE") || upper.contains("GERMANY") || upper.contains("法兰克福") {
            "DE".to_string()
        } else {
            "UN".to_string()
        }
    }

    /// 冷啟動時生成 L0 單節點切片配置並安全寫入指定路徑 (供核心啟動載入)
    pub fn prepare_l0_config(
        node_id: usize,
        routing_mode: &str,
        output_path: &str,
        secret: &str,
    ) -> Result<(), String> {
        let yaml_str = Self::generate_slice_yaml(node_id, routing_mode, secret)?;
        if let Some(parent) = Path::new(output_path).parent() {
            let _ = fs::create_dir_all(parent);
        }
        fs::write(output_path, yaml_str)
            .map_err(|e| format!("寫入 L0 設定檔失敗: {}", e))?;
        Ok(())
    }

    /// 閱後即焚：以零字節覆寫並刪除敏感設定檔
    pub fn shred_file(file_path: &str) -> Result<(), String> {
        let path = Path::new(file_path);
        if !path.exists() {
            return Ok(());
        }
        if let Ok(meta) = fs::metadata(path) {
            let len = meta.len() as usize;
            if len > 0 {
                if let Ok(mut f) = OpenOptions::new().write(true).open(path) {
                    let zeros = vec![0u8; len];
                    let _ = f.write_all(&zeros);
                    let _ = f.flush();
                }
            }
        }
        fs::remove_file(path).map_err(|e| format!("刪除檔案失敗: {}", e))?;
        Ok(())
    }

    /// 生成單節點切片 YAML (僅包含當前選中之 1 顆節點，並完整繼承與重映射母體 proxy-groups/dns/rules)
    pub fn generate_slice_yaml(
        node_id: usize,
        routing_mode: &str,
        secret: &str,
    ) -> Result<String, String> {
        let vault_p = VAULT_PROXIES.read().unwrap();
        let target_node = vault_p.get(node_id)
            .or_else(|| vault_p.first())
            .ok_or_else(|| "金庫中無可用節點".to_string())?;

        let node_name = target_node.get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("Node")
            .to_string();

        let vault_t = VAULT_BASE_TEMPLATE.read().unwrap();
        let base_doc = vault_t.as_ref();

        let valid_mode = match routing_mode.to_lowercase().as_str() {
            "global" => "global",
            "direct" => "direct",
            _ => "rule",
        };

        let mut buffer = String::new();
        buffer.push_str("# Tianhe Network Rust Core Sliced Configuration\n");
        buffer.push_str("mixed-port: 7890\n");
        buffer.push_str("allow-lan: false\n");
        buffer.push_str(&format!("mode: {}\n", valid_mode));
        buffer.push_str("log-level: silent\n");
        buffer.push_str("ipv6: false\n");
        buffer.push_str("tcp-concurrent: true\n");
        buffer.push_str("unified-delay: true\n");
        buffer.push_str("external-controller: 127.0.0.1:9090\n");
        buffer.push_str(&format!("secret: \"{}\"\n", secret));
        buffer.push_str("geo-auto-update: false\n");
        buffer.push_str("geodata-mode: false\n\n");

        // TUN 區塊
        let is_tun = routing_mode.to_lowercase() == "tun";
        buffer.push_str(&format!("tun:\n  enable: {}\n  stack: gvisor\n  dns-hijack:\n    - \"any:53\"\n    - \"tcp://any:53\"\n  auto-route: true\n  auto-detect-interface: true\n\n", is_tun));

        // Sniffer 區塊
        buffer.push_str("sniffer:\n  enable: true\n  sniff:\n    TLS:\n      ports: [443, 8443]\n    HTTP:\n      ports: [80, 8080-8880]\n  force-domain:\n    - \"+.netflix.com\"\n    - \"+.spotify.com\"\n  skip-domain:\n    - \"Mijia Cloud\"\n\n");

        // DNS 區塊 (繼承並清洗 *)
        if let Some(dns_val) = base_doc.and_then(|d| d.get("dns")) {
            let mut dns_map = dns_val.as_mapping().cloned().unwrap_or_default();
            dns_map.insert(Value::String("enable".to_string()), Value::Bool(true));
            dns_map.insert(Value::String("listen".to_string()), Value::String("0.0.0.0:1053".to_string()));
            dns_map.insert(Value::String("ipv6".to_string()), Value::Bool(false));
            dns_map.insert(Value::String("enhanced-mode".to_string()), Value::String("fake-ip".to_string()));
            dns_map.insert(Value::String("fake-ip-range".to_string()), Value::String("198.18.0.1/16".to_string()));
            dns_map.insert(Value::String("cache-algorithm".to_string()), Value::String("arc".to_string()));
            buffer.push_str(&format!("dns:\n{}\n", Self::indent_yaml(&Value::Mapping(dns_map), 2)));
        } else {
            let cf_doh = obfstr!("https://cloudflare-dns.com/dns-query").to_string();
            let ali_doh = obfstr!("https://dns.alidns.com/dns-query").to_string();
            buffer.push_str(&format!(
                "dns:\n  enable: true\n  listen: 0.0.0.0:1053\n  ipv6: false\n  enhanced-mode: fake-ip\n  fake-ip-range: 198.18.0.1/16\n  cache-algorithm: arc\n  default-nameserver:\n    - 223.5.5.5\n    - 119.29.29.29\n  nameserver:\n    - {}\n    - {}\n\n",
                ali_doh, cf_doh
            ));
        }

        // 單節點 proxies 陣列 (僅寫 1 顆節點)
        buffer.push_str("proxies:\n");
        buffer.push_str(&format!("  - {}\n\n", Self::indent_yaml(target_node, 4).trim_start()));

        // 策略組 proxy-groups (繼承與重映射母體，確保懸空節點收斂至 targetNode)
        let mut final_groups: Vec<Mapping> = Vec::new();
        let special_keywords: HashSet<&str> = ["DIRECT", "REJECT", "PASS", "COMPATIBLE", "GLOBAL"].into_iter().collect();

        if let Some(raw_groups) = base_doc.and_then(|d| d.get("proxy-groups")).and_then(|g| g.as_sequence()) {
            let valid_group_names: HashSet<String> = raw_groups
                .iter()
                .filter_map(|g| g.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                .collect();

            for rg in raw_groups {
                if let Some(mut gmap) = rg.as_mapping().cloned() {
                    let gname = gmap.get(&Value::String("name".to_string())).and_then(|v| v.as_str()).unwrap_or("").to_string();
                    if gname.is_empty() { continue; }

                    let mut new_proxies: Vec<String> = Vec::new();
                    let mut seen: HashSet<String> = HashSet::new();
                    if let Some(orig) = gmap.get(&Value::String("proxies".to_string())).and_then(|p| p.as_sequence()) {
                        for entry in orig {
                            if let Some(s) = entry.as_str() {
                                let trimmed = s.trim();
                                if trimmed.is_empty() { continue; }
                                if valid_group_names.contains(trimmed) || special_keywords.contains(trimmed.to_uppercase().as_str()) {
                                    if seen.insert(trimmed.to_string()) {
                                        new_proxies.push(trimmed.to_string());
                                    }
                                } else if seen.insert(node_name.clone()) {
                                    new_proxies.push(node_name.clone());
                                }
                            }
                        }
                    }

                    if !seen.contains(&node_name) {
                        new_proxies.insert(0, node_name.clone());
                    } else {
                        new_proxies.retain(|x| x != &node_name);
                        new_proxies.insert(0, node_name.clone());
                    }

                    let val_list: Vec<Value> = new_proxies.into_iter().map(Value::String).collect();
                    gmap.insert(Value::String("proxies".to_string()), Value::Sequence(val_list));
                    final_groups.push(gmap);
                }
            }
        }

        // 保底注入 PROXY 與 GLOBAL 策略組
        let has_proxy = final_groups.iter().any(|g| g.get(&Value::String("name".to_string())).and_then(|n| n.as_str()) == Some("PROXY"));
        if !has_proxy {
            let mut m = Mapping::new();
            m.insert(Value::String("name".to_string()), Value::String("PROXY".to_string()));
            m.insert(Value::String("type".to_string()), Value::String("select".to_string()));
            m.insert(Value::String("proxies".to_string()), Value::Sequence(vec![Value::String(node_name.clone()), Value::String("DIRECT".to_string())]));
            final_groups.insert(0, m);
        }

        let has_global = final_groups.iter().any(|g| g.get(&Value::String("name".to_string())).and_then(|n| n.as_str()) == Some("GLOBAL"));
        if !has_global {
            let mut m = Mapping::new();
            m.insert(Value::String("name".to_string()), Value::String("GLOBAL".to_string()));
            m.insert(Value::String("type".to_string()), Value::String("select".to_string()));
            m.insert(Value::String("proxies".to_string()), Value::Sequence(vec![Value::String(node_name.clone()), Value::String("PROXY".to_string()), Value::String("DIRECT".to_string())]));
            final_groups.push(m);
        }

        buffer.push_str("proxy-groups:\n");
        for grp in final_groups {
            buffer.push_str(&format!("  - {}\n", Self::indent_yaml(&Value::Mapping(grp), 4).trim_start()));
        }
        buffer.push('\n');

        // 繼承母體的 rule-providers
        if let Some(rp_val) = base_doc.and_then(|d| d.get("rule-providers")) {
            buffer.push_str(&format!("rule-providers:\n{}\n\n", Self::indent_yaml(rp_val, 2)));
        }

        // 繼承母體的 rules
        if let Some(rules_val) = base_doc.and_then(|d| d.get("rules")) {
            buffer.push_str(&format!("rules:\n{}\n", Self::indent_yaml(rules_val, 2)));
        } else {
            buffer.push_str("rules:\n  - DOMAIN-SUFFIX,local,DIRECT\n  - IP-CIDR,127.0.0.0/8,DIRECT\n  - GEOSITE,gfw,PROXY\n  - GEOSITE,geolocation-!cn,PROXY\n  - GEOIP,CN,DIRECT\n  - MATCH,PROXY\n");
        }

        Ok(buffer)
    }

    /// 在連線狀態下，直推 9090 端口熱重載單節點切片並切斷舊長連線 (< 20ms 瞬切)
    pub async fn select_node_and_apply(
        node_id: usize,
        routing_mode: &str,
        secret: &str,
    ) -> Result<(), String> {
        let yaml_str = Self::generate_slice_yaml(node_id, routing_mode, secret)?;

        let client = reqwest::Client::builder()
            .no_proxy()
            .timeout(std::time::Duration::from_millis(1500))
            .build()
            .map_err(|e| format!("HTTP Client 建立失敗: {}", e))?;

        let payload_json = serde_json::json!({
            "payload": yaml_str
        });

        // 1. PUT http://127.0.0.1:9090/configs?force=true
        let put_res = client
            .put("http://127.0.0.1:9090/configs?force=true")
            .header("Authorization", format!("Bearer {}", secret))
            .header("Content-Type", "application/json")
            .json(&payload_json)
            .send()
            .await
            .map_err(|e| format!("PUT /configs 失敗: {}", e))?;

        if !put_res.status().is_success() {
            return Err(format!("核心重載返回狀態碼: {}", put_res.status()));
        }

        // 2. DELETE http://127.0.0.1:9090/connections 瞬切出口
        let _ = client
            .delete("http://127.0.0.1:9090/connections")
            .header("Authorization", format!("Bearer {}", secret))
            .send()
            .await;

        Ok(())
    }

    fn indent_yaml(val: &Value, indent: usize) -> String {
        let raw = serde_yaml::to_string(val).unwrap_or_default();
        let pad = " ".repeat(indent);
        raw.lines()
            .filter(|l| !l.starts_with("---"))
            .map(|l| format!("{}{}", pad, l))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_YAML: &str = r#"
proxies:
  - name: "🇭🇰 香港 01 | 專線"
    type: vmess
    server: 1.2.3.4
    port: 443
    uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  - name: "🇯🇵 日本 02 | 影音"
    type: trojan
    server: 5.6.7.8
    port: 443
    password: "secret_trojan_password"
proxy-groups:
  - name: "天河網絡"
    type: select
    proxies:
      - "🇭🇰 香港 01 | 專線"
      - "🇯🇵 日本 02 | 影音"
      - DIRECT
rules:
  - DOMAIN-SUFFIX,google.com,天河網絡
  - MATCH,DIRECT
"#;

    #[test]
    fn test_yaml_engine_parse_and_vault() {
        let descriptors = YamlEngine::parse_and_vault(SAMPLE_YAML).expect("Parse should succeed");
        assert_eq!(descriptors.len(), 2);
        assert_eq!(descriptors[0].name, "🇭🇰 香港 01 | 專線");
        assert_eq!(descriptors[0].country_code, "HK");
        assert_eq!(descriptors[1].name, "🇯🇵 日本 02 | 影音");
        assert_eq!(descriptors[1].country_code, "JP");

        let desc_json = serde_json::to_string(&descriptors).unwrap();
        // 驗證 UI 零機密：回傳給 Dart 的資料絕不包含 IP 或密碼/UUID！
        assert!(!desc_json.contains("1.2.3.4"));
        assert!(!desc_json.contains("a1b2c3d4"));
        assert!(!desc_json.contains("secret_trojan_password"));
    }

    #[test]
    fn test_generate_slice_yaml_template_merge() {
        let _ = YamlEngine::parse_and_vault(SAMPLE_YAML);
        let slice = YamlEngine::generate_slice_yaml(0, "rule", "test_secret").expect("Slice should succeed");
        assert!(slice.contains("mixed-port: 7890"));
        assert!(slice.contains("🇭🇰 香港 01 | 專線"));
        assert!(slice.contains("DOMAIN-SUFFIX,google.com,天河網絡"));
        // 單節點切片驗證：proxies 區塊絕不能包含未選中的第 2 顆節點
        assert!(!slice.contains("🇯🇵 日本 02 | 影音"));
    }
}
