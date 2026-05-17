use std::ffi::{c_char, CStr};

use crate::logger;
use crate::pty_manager;

fn cstr(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().unwrap_or("").to_string()
}

fn cstr_opt(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap_or("").to_string();
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

#[no_mangle]
pub extern "C" fn rterm_spawn(
    id: *const c_char,
    shell: *const c_char,
    executable: *const c_char,
    working_dir: *const c_char,
    cols: u16,
    rows: u16,
) -> i32 {
    let id_s = cstr(id);
    let shell_s = cstr(shell);
    let exe_s = cstr_opt(executable);
    let wd_s = cstr_opt(working_dir);

    logger::log_info(&format!(
        "rterm_spawn: id={}, shell={}, exe={:?}, wd={:?}, cols={}, rows={}",
        id_s, shell_s, exe_s, wd_s, cols, rows
    ));

    match pty_manager::spawn(&id_s, &shell_s, exe_s.as_deref(), wd_s.as_deref(), &[], cols, rows)
    {
        Ok(()) => {
            logger::log_info(&format!("rterm_spawn OK: id={}", id_s));
            0
        }
        Err(e) => {
            logger::log_error(&format!("rterm_spawn FAILED: id={}, error={}", id_s, e));
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn rterm_write(
    id: *const c_char,
    data: *const u8,
    len: u32,
) -> i32 {
    let id_s = cstr(id);
    if data.is_null() || len == 0 {
        return 0;
    }
    logger::log_info(&format!("rterm_write: id={}, len={}", id_s, len));
    let slice = unsafe { std::slice::from_raw_parts(data, len as usize) };
    match pty_manager::write_to(&id_s, slice) {
        Ok(n) => n as i32,
        Err(e) => {
            logger::log_error(&format!("rterm_write FAILED: id={}, error={}", id_s, e));
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn rterm_read(
    id: *const c_char,
    buf: *mut u8,
    cap: u32,
) -> i32 {
    let id_s = cstr(id);
    if buf.is_null() || cap == 0 {
        return 0;
    }
    let slice = unsafe { std::slice::from_raw_parts_mut(buf, cap as usize) };
    match pty_manager::read_from(&id_s, slice) {
        Ok(n) => n as i32,
        Err(e) => {
            logger::log_error(&format!("rterm_read FAILED: id={}, error={}", id_s, e));
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn rterm_available(id: *const c_char) -> i32 {
    let id_s = cstr(id);
    match pty_manager::available(&id_s) {
        Ok(n) => n as i32,
        Err(e) => {
            logger::log_error(&format!(
                "rterm_available FAILED: id={}, error={}",
                id_s, e
            ));
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn rterm_resize(
    id: *const c_char,
    cols: u16,
    rows: u16,
) -> i32 {
    let id_s = cstr(id);
    logger::log_info(&format!(
        "rterm_resize: id={}, cols={}, rows={}",
        id_s, cols, rows
    ));
    match pty_manager::resize(&id_s, cols, rows) {
        Ok(()) => 0,
        Err(e) => {
            logger::log_error(&format!("rterm_resize FAILED: id={}, error={}", id_s, e));
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn rterm_close(id: *const c_char) -> i32 {
    let id_s = cstr(id);
    logger::log_info(&format!("rterm_close: id={}", id_s));
    match pty_manager::close(&id_s) {
        Ok(()) => 0,
        Err(e) => {
            logger::log_error(&format!("rterm_close FAILED: id={}, error={}", id_s, e));
            -1
        }
    }
}
