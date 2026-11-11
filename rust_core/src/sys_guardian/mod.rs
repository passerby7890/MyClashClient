// rust_core/src/sys_guardian/mod.rs
#[cfg(target_os = "windows")]
pub mod windows;

pub struct SysGuardian;

impl SysGuardian {
    /// 設定作業系統全域代理 (Windows 耗時 < 1ms)
    pub fn set_system_proxy(enable: bool, port: u16) -> Result<(), String> {
        #[cfg(target_os = "windows")]
        {
            windows::set_windows_system_proxy(enable, port)
        }
        #[cfg(not(target_os = "windows"))]
        {
            let _ = (enable, port);
            Ok(())
        }
    }

    /// 綁定系統級進程防殭屍守護 (Windows Job Object)
    pub fn ensure_process_guardian() -> bool {
        #[cfg(target_os = "windows")]
        {
            windows::init_job_guardian()
        }
        #[cfg(not(target_os = "windows"))]
        {
            true
        }
    }

    /// 綁定特定子進程 PID 至 Job Object
    pub fn assign_process_to_job(pid: u32) -> bool {
        #[cfg(target_os = "windows")]
        {
            windows::assign_pid_to_job(pid)
        }
        #[cfg(not(target_os = "windows"))]
        {
            let _ = pid;
            true
        }
    }
}
