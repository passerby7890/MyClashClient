// rust_core/src/lib.rs
pub mod net_racer;
pub mod ping_tokio;
pub mod sys_guardian;
pub mod vault_crypto;
pub mod yaml_engine;

use net_racer::NetRacer;
use ping_tokio::PingEngine;
use serde::Serialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;
use sys_guardian::SysGuardian;
use tokio::runtime::Runtime;
use vault_crypto::VaultCrypto;
use yaml_engine::YamlEngine;

/// 全域單例 Tokio 多執行緒非阻塞 Runtime (Mandatory Fix 5: 避免每次呼叫重建 Runtime)
static TOKIO_RT: OnceLock<Runtime> = OnceLock::new();

fn get_runtime() -> &'static Runtime {
    TOKIO_RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(4)
            .thread_name("tianhe-rust-worker")
            .build()
            .expect("Failed to create Tokio runtime")
    })
}

#[derive(Serialize)]
struct ApiResponse<T: Serialize> {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Serialize)]
struct RaceAndVaultResult {
    winner_host: String,
    nodes: Vec<yaml_engine::SafeNodeDescriptor>,
    encrypted_backup: String,
}

fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

fn json_ok<T: Serialize>(data: T) -> *mut c_char {
    let resp = ApiResponse {
        ok: true,
        data: Some(data),
        error: None,
    };
    to_c_string(serde_json::to_string(&resp).unwrap_or_else(|_| r#"{"ok":false,"error":"serialize"}"#.to_string()))
}

fn json_err(err: String) -> *mut c_char {
    let resp: ApiResponse<()> = ApiResponse {
        ok: false,
        data: None,
        error: Some(err),
    };
    to_c_string(serde_json::to_string(&resp).unwrap_or_else(|_| r#"{"ok":false,"error":"unknown"}"#.to_string()))
}

unsafe fn from_c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    Some(CStr::from_ptr(ptr).to_string_lossy().into_owned())
}

// ============================================================================
// 🌐 C-ABI FFI 導出介面 (100% 相容 Dart dart:ffi)
// ============================================================================

/// 1. 初始化原生引擎、Tokio Runtime 與系統守護
#[no_mangle]
pub extern "C" fn tianhe_init() -> bool {
    let _ = get_runtime();
    SysGuardian::ensure_process_guardian()
}

/// 2. 釋放由 Rust 分配並回傳給 Dart 的 C 字串記憶體 (Mandatory Fix 5: 防 Memory Leak)
#[no_mangle]
pub unsafe extern "C" fn tianhe_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// 3. 取得引擎版本識別字串 (需由 Dart 端呼叫 tianhe_free_string 釋放)
#[no_mangle]
pub extern "C" fn tianhe_engine_version() -> *mut c_char {
    to_c_string("3.4.0".to_string())
}

/// 4. [VaultCrypto] AES-256-CBC 解密 (金鑰全程封鎖在機器指令與清零記憶體中)
#[no_mangle]
pub unsafe extern "C" fn tianhe_decrypt_config(ciphertext_ptr: *const c_char) -> *mut c_char {
    let ciphertext = match from_c_str(ciphertext_ptr) {
        Some(s) => s,
        None => return json_err("null ciphertext pointer".to_string()),
    };

    match VaultCrypto::decrypt_cbc(&ciphertext) {
        Ok(plain) => json_ok(plain),
        Err(e) => json_err(e),
    }
}

/// 5. [VaultCrypto] 加密明文設定 (測試或匯出用)
#[no_mangle]
pub unsafe extern "C" fn tianhe_encrypt_config(plaintext_ptr: *const c_char) -> *mut c_char {
    let plaintext = match from_c_str(plaintext_ptr) {
        Some(s) => s,
        None => return json_err("null plaintext pointer".to_string()),
    };

    match VaultCrypto::encrypt_cbc(&plaintext) {
        Ok(cipher) => json_ok(cipher),
        Err(e) => json_err(e),
    }
}

/// 6. [NetRacer + VaultCrypto] 直連阿里雲 OSS 獲取並解密動態設定
#[no_mangle]
pub extern "C" fn tianhe_fetch_oss_config() -> *mut c_char {
    let rt = get_runtime();
    let res = rt.block_on(NetRacer::fetch_oss_dynamic_config());
    match res {
        Ok(config_json) => json_ok(config_json),
        Err(e) => json_err(e),
    }
}

/// 7. [NetRacer + YamlEngine] Happy Eyeballs 2.5s 並發競速下載訂閱 + 在 Rust 記憶體內完成解析隔離
/// 僅回傳 SafeNodeDescriptor JSON 與勝出主機給 Dart，真實 IP/UUID/密碼 0 暴露！
#[no_mangle]
pub unsafe extern "C" fn tianhe_race_and_vault_subscription(
    hosts_json_ptr: *const c_char,
    relative_path_ptr: *const c_char,
) -> *mut c_char {
    let hosts_json = from_c_str(hosts_json_ptr).unwrap_or_else(|| "[]".to_string());
    let relative_path = match from_c_str(relative_path_ptr) {
        Some(s) => s,
        None => return json_err("null relative_path".to_string()),
    };

    let hosts: Vec<String> = serde_json::from_str(&hosts_json).unwrap_or_default();
    let rt = get_runtime();

    let res = rt.block_on(async {
        let (winner, raw_yaml) = NetRacer::race_download_subscription(hosts, &relative_path).await?;
        let descriptors = YamlEngine::parse_and_vault(&raw_yaml)?;
        let cipher = VaultCrypto::encrypt_cbc(&raw_yaml)?;
        Ok::<RaceAndVaultResult, String>(RaceAndVaultResult {
            winner_host: winner,
            nodes: descriptors,
            encrypted_backup: format!("RUST_ENC:{}", cipher),
        })
    });

    match res {
        Ok(result) => json_ok(result),
        Err(e) => json_err(e),
    }
}

/// 8. [YamlEngine] 解析傳入的 YAML 並存入 Rust 靜態金庫 (回傳 SafeNodeDescriptor JSON)
#[no_mangle]
pub unsafe extern "C" fn tianhe_parse_yaml(raw_yaml_ptr: *const c_char) -> *mut c_char {
    let raw_yaml = match from_c_str(raw_yaml_ptr) {
        Some(s) => s,
        None => return json_err("null raw_yaml".to_string()),
    };

    match YamlEngine::parse_and_vault(&raw_yaml) {
        Ok(descriptors) => json_ok(descriptors),
        Err(e) => json_err(e),
    }
}

/// 9. [YamlEngine] 冷啟動前準備 L0 單節點切片設定檔寫入私密路徑 (Mandatory Fix 4)
#[no_mangle]
pub unsafe extern "C" fn tianhe_prepare_l0_config(
    node_id: usize,
    routing_mode_ptr: *const c_char,
    output_path_ptr: *const c_char,
    secret_ptr: *const c_char,
) -> bool {
    let routing_mode = from_c_str(routing_mode_ptr).unwrap_or_else(|| "rule".to_string());
    let output_path = match from_c_str(output_path_ptr) {
        Some(s) => s,
        None => return false,
    };
    let secret = from_c_str(secret_ptr).unwrap_or_else(VaultCrypto::get_core_secret);

    YamlEngine::prepare_l0_config(node_id, &routing_mode, &output_path, &secret).is_ok()
}

/// 10. [YamlEngine] 閱後即焚安全覆寫並刪除臨時設定檔
#[no_mangle]
pub unsafe extern "C" fn tianhe_shred_file(path_ptr: *const c_char) -> bool {
    match from_c_str(path_ptr) {
        Some(p) => YamlEngine::shred_file(&p).is_ok(),
        None => false,
    }
}

/// 11. [YamlEngine] 連線中直接從 Rust 金庫合成切片並推入 9090 端口 + 切斷舊長連線 (Mandatory Fix 4)
#[no_mangle]
pub unsafe extern "C" fn tianhe_select_node(
    node_id: usize,
    routing_mode_ptr: *const c_char,
    secret_ptr: *const c_char,
) -> bool {
    let routing_mode = from_c_str(routing_mode_ptr).unwrap_or_else(|| "rule".to_string());
    let secret = from_c_str(secret_ptr).unwrap_or_else(VaultCrypto::get_core_secret);

    let rt = get_runtime();
    rt.block_on(YamlEngine::select_node_and_apply(node_id, &routing_mode, &secret))
        .is_ok()
}

/// 12. [PingEngine] Tokio 50 路並發微秒級測速 (Mandatory Fix 2: 從 Rust 金庫讀取 IP/Port，零參數洩漏)
#[no_mangle]
pub extern "C" fn tianhe_batch_ping(timeout_ms: u64) -> *mut c_char {
    let rt = get_runtime();
    let res = rt.block_on(PingEngine::batch_ping_vault_nodes(timeout_ms));
    match res {
        Ok(items) => json_ok(items),
        Err(e) => json_err(e),
    }
}

/// 13. [PingEngine] 原子操作一鍵立即中止測速
#[no_mangle]
pub extern "C" fn tianhe_cancel_ping() {
    PingEngine::cancel_all();
}

/// 14. [SysGuardian] 原生系統代理秒開秒關 (Win32 API < 1ms)
#[no_mangle]
pub extern "C" fn tianhe_set_system_proxy(enable: bool, port: u16) -> bool {
    SysGuardian::set_system_proxy(enable, port).is_ok()
}

/// 15. [SysGuardian] 將外部子進程 PID 綁定至 Windows Job Object (殺主殺子防殭屍進程)
#[no_mangle]
pub extern "C" fn tianhe_assign_job_pid(pid: u32) -> bool {
    SysGuardian::assign_process_to_job(pid)
}

/// 16. [NetRacer + VaultCrypto] 全方位 DoH + OSS 並行搶答獲取遠端動態設定 JSON
#[no_mangle]
pub extern "C" fn tianhe_resolve_remote_config() -> *mut c_char {
    let rt = get_runtime();
    let res = rt.block_on(NetRacer::resolve_remote_config_parallel());
    match res {
        Ok(json_str) => json_ok(json_str),
        Err(e) => json_err(e),
    }
}
