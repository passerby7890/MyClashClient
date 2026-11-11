// rust_core/src/ping_tokio/mod.rs
use crate::yaml_engine::VAULT_PROXIES;
use lazy_static::lazy_static;
use serde::Serialize;
use std::net::ToSocketAddrs;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::net::TcpStream;
use tokio::sync::Semaphore;
use tokio::task::JoinSet;
use tokio::time::{timeout, Instant};

lazy_static! {
    static ref CANCEL_FLAG: Arc<AtomicBool> = Arc::new(AtomicBool::new(false));
}

#[derive(Serialize)]
pub struct PingResultItem {
    pub id: usize,
    pub latency: i64, // ms; -1 indicates timeout or failure
}

pub struct PingEngine;

impl PingEngine {
    /// 一鍵中止正在進行的批次測速
    pub fn cancel_all() {
        CANCEL_FLAG.store(true, Ordering::SeqCst);
    }

    /// 【強制修正 2：UI 零機密】直接從 Rust 靜態金庫 VAULT_PROXIES 讀取真實 server 與 port
    /// 外部 Dart 端完全不傳入、也看不見任何節點 IP 與端口
    /// 在 Tokio 多執行緒池上發射最多 50 路微秒級併發測速任務
    pub async fn batch_ping_vault_nodes(timeout_ms: u64) -> Result<Vec<PingResultItem>, String> {
        CANCEL_FLAG.store(false, Ordering::SeqCst);

        // 1. 從靜態金庫提取目標 (僅擷取 index, server, port)
        let targets: Vec<(usize, String, u16)> = {
            let vault = VAULT_PROXIES.read().map_err(|_| "讀取節點金庫鎖失敗".to_string())?;
            vault
                .iter()
                .enumerate()
                .filter_map(|(idx, node)| {
                    let server = node.get("server")
                        .and_then(|s| s.as_str())
                        .map(|s| s.trim().to_string())?;
                    let port = node.get("port").and_then(|p| {
                        p.as_u64()
                            .or_else(|| p.as_str().and_then(|s| s.parse::<u64>().ok()))
                    })? as u16;
                    Some((idx, server, port))
                })
                .collect()
        };

        if targets.is_empty() {
            return Ok(Vec::new());
        }

        // 2. 控制最大併發數為 50 路，並透過 Semaphore 節流
        let semaphore = Arc::new(Semaphore::new(50));
        let mut join_set = JoinSet::new();
        let effective_timeout = if timeout_ms == 0 { 1500 } else { timeout_ms };

        for (id, server, port) in targets {
            let sem_clone = Arc::clone(&semaphore);
            let cancel_clone = Arc::clone(&CANCEL_FLAG);

            join_set.spawn(async move {
                let _permit = match sem_clone.acquire().await {
                    Ok(p) => p,
                    Err(_) => return PingResultItem { id, latency: -1 },
                };

                if cancel_clone.load(Ordering::Relaxed) {
                    return PingResultItem { id, latency: -1 };
                }

                let target_addr = format!("{}:{}", server, port);
                // 預先嘗試系統非阻塞解析或直連 (Rust native async)
                let start = Instant::now();
                let connect_fut = async {
                    // 若為域名，先透過 tokio::net::lookup_host 解析
                    if let Ok(mut addrs) = tokio::net::lookup_host(&target_addr).await {
                        if let Some(sock_addr) = addrs.next() {
                            return TcpStream::connect(sock_addr).await;
                        }
                    }
                    // 若為純 IP 或無法解析
                    if let Ok(sock) = target_addr.to_socket_addrs().map(|mut it| it.next()) {
                        if let Some(addr) = sock {
                            return TcpStream::connect(addr).await;
                        }
                    }
                    TcpStream::connect(&target_addr).await
                };

                let res = timeout(Duration::from_millis(effective_timeout), connect_fut).await;
                let latency = match res {
                    Ok(Ok(_stream)) => {
                        let ms = start.elapsed().as_millis() as i64;
                        if ms == 0 { 1 } else { ms }
                    }
                    _ => -1,
                };

                PingResultItem { id, latency }
            });
        }

        let mut results = Vec::new();
        while let Some(res) = join_set.join_next().await {
            if let Ok(item) = res {
                results.push(item);
            }
        }

        // 按照 node id 升序排列回傳
        results.sort_by_key(|r| r.id);
        Ok(results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::yaml_engine::YamlEngine;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn test_ping_engine_reads_vault_only() {
        // 啟動一個本機臨時 TCP 監聽端口來測試真實毫秒測速
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();

        tokio::spawn(async move {
            let _ = listener.accept().await;
        });

        let sample_yaml = format!(
            "proxies:\n  - name: \"LocalTestNode\"\n    type: ss\n    server: 127.0.0.1\n    port: {}\n",
            port
        );
        YamlEngine::parse_and_vault(&sample_yaml).unwrap();

        let res = PingEngine::batch_ping_vault_nodes(1000).await.unwrap();
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].id, 0);
        assert!(res[0].latency >= 1 && res[0].latency < 500, "Latency should be fast local TCP handshake");
    }
}

