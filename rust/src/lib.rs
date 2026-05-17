mod logger;
mod shell;
mod pty_manager;
mod ffi_bridge;

use ctor::ctor;

#[ctor]
fn dll_init() {
    logger::init();
}

pub use shell::{default_config_dir, default_shell_priority};
