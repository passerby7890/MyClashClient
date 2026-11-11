// rust_core/src/sys_guardian/windows.rs
use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::ptr;
use std::sync::OnceLock;
use windows_sys::Win32::Foundation::CloseHandle;
use windows_sys::Win32::Networking::WinInet::{
    InternetSetOptionW, INTERNET_OPTION_REFRESH, INTERNET_OPTION_SETTINGS_CHANGED,
};
use windows_sys::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
    SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows_sys::Win32::System::Registry::{
    RegCloseKey, RegOpenKeyExW, RegSetValueExW, HKEY, HKEY_CURRENT_USER, KEY_SET_VALUE, REG_DWORD,
    REG_SZ,
};
use windows_sys::Win32::System::Threading::{OpenProcess, PROCESS_SET_QUOTA, PROCESS_TERMINATE};

fn to_wide_null(s: &str) -> Vec<u16> {
    OsStr::new(s).encode_wide().chain(std::iter::once(0)).collect()
}

/// 註冊表即時切換系統代理 + WinINet FFI 立即生效 (免重啟瀏覽器)
pub fn set_windows_system_proxy(enable: bool, port: u16) -> Result<(), String> {
    let subkey = to_wide_null(r"Software\Microsoft\Windows\CurrentVersion\Internet Settings");
    let mut hkey: HKEY = 0;

    unsafe {
        let open_res = RegOpenKeyExW(
            HKEY_CURRENT_USER,
            subkey.as_ptr(),
            0,
            KEY_SET_VALUE,
            &mut hkey,
        );
        if open_res != 0 {
            return Err(format!("開啟系統代理註冊表鍵失敗: error {}", open_res));
        }

        // 1. 寫入 ProxyEnable (DWORD: 1 或 0)
        let enable_val: u32 = if enable { 1 } else { 0 };
        let val_name_enable = to_wide_null("ProxyEnable");
        let res_enable = RegSetValueExW(
            hkey,
            val_name_enable.as_ptr(),
            0,
            REG_DWORD,
            &enable_val as *const u32 as *const u8,
            std::mem::size_of::<u32>() as u32,
        );

        // 2. 若啟用代理，寫入 ProxyServer (REG_SZ: 127.0.0.1:7890) 與 ProxyOverride
        if enable {
            let server_str = format!("127.0.0.1:{}", port);
            let server_wide = to_wide_null(&server_str);
            let val_name_server = to_wide_null("ProxyServer");
            let _ = RegSetValueExW(
                hkey,
                val_name_server.as_ptr(),
                0,
                REG_SZ,
                server_wide.as_ptr() as *const u8,
                (server_wide.len() * 2) as u32,
            );

            let override_str = "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>";
            let override_wide = to_wide_null(override_str);
            let val_name_override = to_wide_null("ProxyOverride");
            let _ = RegSetValueExW(
                hkey,
                val_name_override.as_ptr(),
                0,
                REG_SZ,
                override_wide.as_ptr() as *const u8,
                (override_wide.len() * 2) as u32,
            );
        }

        RegCloseKey(hkey);

        if res_enable != 0 {
            return Err(format!("寫入 ProxyEnable 失敗: error {}", res_enable));
        }

        // 3. 呼叫 WinINet API 立即刷新全局網路設定 (無需重啟瀏覽器)
        InternetSetOptionW(ptr::null_mut(), INTERNET_OPTION_SETTINGS_CHANGED, ptr::null(), 0);
        InternetSetOptionW(ptr::null_mut(), INTERNET_OPTION_REFRESH, ptr::null(), 0);
    }

    Ok(())
}

/// 守護對象包裝器：確保應用退出時 Drop 解構自動還原關閉代理，防止斷網！
pub struct ProxyDropGuard {
    job_handle: isize,
}

impl Drop for ProxyDropGuard {
    fn drop(&mut self) {
        let _ = set_windows_system_proxy(false, 7890);
    }
}

static JOB_GUARDIAN: OnceLock<ProxyDropGuard> = OnceLock::new();

pub fn init_job_guardian() -> bool {
    JOB_GUARDIAN.get_or_init(|| unsafe {
        let job = CreateJobObjectW(ptr::null(), ptr::null());
        if job != 0 {
            let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                &info as *const _ as *const _,
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            );
        }
        ProxyDropGuard { job_handle: job }
    });
    true
}

/// 將外部子進程 (如 mihomo.exe PID) 關聯綁定至此 Job Object
/// 主程式一旦退出或遭強殺，系統核心立即自動回收子進程，徹底杜絕殭屍進程！
pub fn assign_pid_to_job(pid: u32) -> bool {
    init_job_guardian();
    if let Some(guard) = JOB_GUARDIAN.get() {
        if guard.job_handle == 0 {
            return false;
        }
        unsafe {
            let proc_handle = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, 0, pid);
            if proc_handle == 0 {
                return false;
            }
            let res = AssignProcessToJobObject(guard.job_handle, proc_handle);
            CloseHandle(proc_handle);
            return res != 0;
        }
    }
    false
}
