// rust_core/src/net_racer/mod.rs
use crate::vault_crypto::VaultCrypto;
use futures::future::select_ok;
use std::time::Duration;

pub struct NetRacer;

impl NetRacer {
    /// 獲取當前平台的純淨品牌 User-Agent (消除任何開源敏感字串)
    pub fn get_platform_ua() -> &'static str {
        #[cfg(target_os = "windows")]
        {
            "TianheNetwork/3.4.0 (Windows)"
        }
        #[cfg(target_os = "android")]
        {
            "TianheNetwork/3.4.0 (Android)"
        }
        #[cfg(target_os = "macos")]
        {
            "TianheNetwork/3.4.0 (macOS)"
        }
        #[cfg(not(any(target_os = "windows", target_os = "android", target_os = "macos")))]
        {
            "TianheNetwork/3.4.0 (Engine/Rust)"
        }
    }

    /// 建立安全 HTTP 客戶端：
    /// 1. 強制 .no_proxy() 徹底無視系統 HTTP 代理 (防 Fiddler/Reqable/HttpCanary 抓包)
    /// 2. .danger_accept_invalid_certs(true) 確保純 IP 端點 (如 8.218/8.219) TLS 握手 100% 成功
    pub fn build_secure_client(timeout_ms: u64) -> Result<reqwest::Client, String> {
        reqwest::Client::builder()
            .no_proxy()
            .danger_accept_invalid_certs(true)
            .timeout(Duration::from_millis(timeout_ms))
            .connect_timeout(Duration::from_millis(timeout_ms.min(2500)))
            .pool_idle_timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| format!("構建安全 HTTP Client 失敗: {}", e))
    }

    /// Happy Eyeballs 2.5s 並發競速下載訂閱內容
    /// 自動修飾相對路徑注入 &flag=meta (具備 flag=clashmeta 自動降級回退)
    pub async fn race_download_subscription(
        candidate_hosts: Vec<String>,
        raw_relative_path: &str,
    ) -> Result<(String, String), String> {
        let mut hosts = candidate_hosts;
        if hosts.is_empty() {
            hosts = VaultCrypto::get_fallback_domains();
        }

        // 確保路徑中帶有 flag=meta 參數 (安全相容)
        let mut path_meta = raw_relative_path.to_string();
        if path_meta.contains("flag=clash") {
            path_meta = path_meta.replace("flag=clash", "flag=meta");
        } else if !path_meta.contains("flag=") {
            let sep = if path_meta.contains('?') { "&" } else { "?" };
            path_meta = format!("{}{}flag=meta", path_meta, sep);
        }

        let ua = Self::get_platform_ua();

        // 嘗試首選路徑 (flag=meta)
        match Self::execute_race(&hosts, &path_meta, ua, 2500).await {
            Ok((winner, body)) => {
                // 檢查是否返回有效 YAML
                if body.contains("proxies:") || body.contains("proxy-groups:") {
                    return Ok((winner, body));
                }
                // 若返回純 Base64 或舊格式，嘗試回退 flag=clashmeta
                let path_fallback = path_meta.replace("flag=meta", "flag=clashmeta");
                if let Ok((w, b)) = Self::execute_race(&hosts, &path_fallback, ua, 2500).await {
                    return Ok((w, b));
                }
                Ok((winner, body))
            }
            Err(_) => {
                // 2.5s 超時或失敗，以 3500ms 重試全候選競速
                let path_fallback = path_meta.replace("flag=meta", "flag=clashmeta");
                Self::execute_race(&hosts, &path_fallback, ua, 3500).await
            }
        }
    }

    async fn execute_race(
        hosts: &[String],
        relative_path: &str,
        user_agent: &str,
        timeout_ms: u64,
    ) -> Result<(String, String), String> {
        let client = Self::build_secure_client(timeout_ms)?;
        let mut tasks = Vec::new();

        for host in hosts {
            let clean_host = host.trim().trim_end_matches('/').to_string();
            let mut final_host = clean_host.clone();
            if final_host.ends_with("/api/v1") {
                final_host = final_host[..final_host.len() - 7].to_string();
            }
            let target_url = format!("{}{}", final_host, relative_path);
            let c = client.clone();
            let ua = user_agent.to_string();

            tasks.push(Box::pin(async move {
                let resp = c.get(&target_url)
                    .header("User-Agent", ua)
                    .send()
                    .await
                    .map_err(|e| e.to_string())?;

                let status = resp.status();
                if status.is_success() {
                    let text = resp.text().await.map_err(|e| e.to_string())?;
                    let trimmed = text.trim();
                    if !trimmed.is_empty() {
                        return Ok((clean_host, text));
                    }
                }
                Err(format!("端點 {} 響應無效: {}", clean_host, status))
            }));
        }

        if tasks.is_empty() {
            return Err("候選競速端點清單為空".to_string());
        }

        let (winner, _) = select_ok(tasks)
            .await
            .map_err(|_| "全量候選主機並發競速下載皆失敗".to_string())?;

        Ok(winner)
    }

    /// 透過阿里雲香港 OSS 端點獲取並自動解密最新動態線路設定
    pub async fn fetch_oss_dynamic_config() -> Result<String, String> {
        let oss_url = VaultCrypto::get_oss_url();
        let client = Self::build_secure_client(3000)?;

        let resp = client.get(&oss_url)
            .header("User-Agent", Self::get_platform_ua())
            .send()
            .await
            .map_err(|e| format!("請求 OSS 設定失敗: {}", e))?;

        if !resp.status().is_success() {
            return Err(format!("OSS 響應 HTTP 狀態碼非 200: {}", resp.status()));
        }

        let raw_body = resp.text().await.map_err(|e| format!("讀取 OSS 內容失敗: {}", e))?;
        let clean_b64 = raw_body.replace(['"', '\'', ' ', '\n', '\r'], "");

        // 嘗試 AES-256 解密
        match VaultCrypto::decrypt_cbc(&clean_b64) {
            Ok(decrypted) => Ok(decrypted),
            Err(_) => {
                // 若內容本就是未加密 JSON
                if raw_body.trim().starts_with('{') {
                    Ok(raw_body)
                } else {
                    Err("OSS 動態設定內容解密與解析失敗".to_string())
                }
            }
        }
    }

    /// 查詢指定 DoH 端點並自動解密 TXT 記錄
    async fn query_single_doh(endpoint: &str, domain: &str) -> Result<String, String> {
        let client = Self::build_secure_client(3000)?;
        let url = format!("{}?name={}&type=TXT", endpoint, domain);
        let resp = client.get(&url)
            .header("Accept", "application/dns-json")
            .header("User-Agent", Self::get_platform_ua())
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            return Err(format!("DoH status: {}", resp.status()));
        }

        let json_val: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
        let data = json_val.get("Answer")
            .and_then(|a| a.as_array())
            .and_then(|arr| arr.first())
            .and_then(|item| item.get("data"))
            .and_then(|d| d.as_str())
            .ok_or_else(|| "DoH 無 TXT Answer".to_string())?;

        VaultCrypto::decrypt_cbc(data)
    }

    /// 多級 DoH 並發搶答 + OSS 並行競速獲取最新動態遠端設定
    pub async fn resolve_remote_config_parallel() -> Result<String, String> {
        let doh_endpoints = VaultCrypto::get_doh_endpoints();
        let config_domains = VaultCrypto::get_config_domains();

        let mut tasks = Vec::new();
        // 任務 1: 阿里雲 OSS 極速直連
        tasks.push(Box::pin(async move {
            Self::fetch_oss_dynamic_config().await
        }) as std::pin::Pin<Box<dyn std::future::Future<Output = Result<String, String>> + Send>>);

        // 任務 2..N: DoH (Cloudflare / Google / Tencent / Aliyun) 並發 TXT 查詢
        for ep in doh_endpoints {
            for dom in &config_domains {
                let e = ep.clone();
                let d = dom.clone();
                tasks.push(Box::pin(async move {
                    Self::query_single_doh(&e, &d).await
                }));
            }
        }

        match select_ok(tasks).await {
            Ok((config_json, _)) => Ok(config_json),
            Err(_) => {
                // 全數超時時返回硬編碼混淆兜底結構
                let fallbacks = VaultCrypto::get_fallback_domains();
                let primary = fallbacks.first().cloned().unwrap_or_default();
                let backups = if fallbacks.len() > 1 { &fallbacks[1..] } else { &[] };
                let fallback_json = serde_json::json!({
                    "api_domain": primary,
                    "backup_api_domains": backups,
                    "latest_version": "3.4.0",
                    "min_version": "3.0.0",
                    "changelog": ""
                });
                Ok(fallback_json.to_string())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_platform_ua() {
        let ua = NetRacer::get_platform_ua();
        assert!(ua.starts_with("TianheNetwork/3.4.0"));
        assert!(!ua.contains("Clash"));
        assert!(!ua.contains("Meta"));
    }
}
