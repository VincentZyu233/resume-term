use std::env;
use std::path::PathBuf;

pub fn default_shell_priority() -> Vec<&'static str> {
    if cfg!(target_os = "windows") {
        vec!["pwsh", "powershell", "cmd"]
    } else {
        vec!["$SHELL", "bash", "zsh", "sh", "ash"]
    }
}

pub fn default_config_dir() -> PathBuf {
    let home = if cfg!(target_os = "windows") {
        env::var_os("USERPROFILE")
    } else {
        env::var_os("HOME")
    }
    .unwrap_or_else(|| ".".into());

    PathBuf::from(home).join("resume-term").join("config")
}

