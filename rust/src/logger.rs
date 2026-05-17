use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::SystemTime;

static LOG_FILE: std::sync::OnceLock<Mutex<Option<std::fs::File>>> = std::sync::OnceLock::new();

fn log_path() -> PathBuf {
    std::env::current_exe()
        .unwrap_or_else(|_| PathBuf::from("."))
        .parent()
        .unwrap_or_else(|| std::path::Path::new("."))
        .join("latest.log.txt")
}

fn get_log_file() -> &'static Mutex<Option<std::fs::File>> {
    LOG_FILE.get_or_init(|| {
        let path = log_path();
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&path)
            .ok();
        Mutex::new(file)
    })
}

fn timestamp() -> String {
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    format!("[{}]", now)
}

pub fn init() {
    let path = log_path();
    log_info(&format!("Log initialized: {}", path.display()));
    log_info(&format!(
        "Exe path: {}",
        std::env::current_exe()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|_| "unknown".to_string())
    ));
    log_info(&format!(
        "DLL load dir: {}",
        std::env::current_dir()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|_| "unknown".to_string())
    ));
}

pub fn log_info(msg: &str) {
    let guard = get_log_file();
    if let Ok(mut file_opt) = guard.lock() {
        if let Some(file) = file_opt.as_mut() {
            let _ = writeln!(file, "{} [INFO] {}", timestamp(), msg);
            let _ = file.flush();
        }
    }
}

pub fn log_error(msg: &str) {
    let guard = get_log_file();
    if let Ok(mut file_opt) = guard.lock() {
        if let Some(file) = file_opt.as_mut() {
            let _ = writeln!(file, "{} [ERROR] {}", timestamp(), msg);
            let _ = file.flush();
        }
    }
}
