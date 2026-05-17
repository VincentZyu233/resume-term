use std::ffi::{c_char, CStr};

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
    let id = cstr(id);
    let shell = cstr(shell);
    let executable = cstr_opt(executable);
    let working_dir = cstr_opt(working_dir);

    match pty_manager::spawn(&id, &shell, executable.as_deref(), working_dir.as_deref(), &[], cols, rows) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("rterm_spawn error: {}", e);
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
    let id = cstr(id);
    if data.is_null() || len == 0 {
        return 0;
    }
    let slice = unsafe { std::slice::from_raw_parts(data, len as usize) };
    match pty_manager::write_to(&id, slice) {
        Ok(n) => n as i32,
        Err(e) => {
            eprintln!("rterm_write error: {}", e);
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
    let id = cstr(id);
    if buf.is_null() || cap == 0 {
        return 0;
    }
    let slice = unsafe { std::slice::from_raw_parts_mut(buf, cap as usize) };
    match pty_manager::read_from(&id, slice) {
        Ok(n) => n as i32,
        Err(e) => {
            eprintln!("rterm_read error: {}", e);
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn rterm_available(id: *const c_char) -> i32 {
    let id = cstr(id);
    match pty_manager::available(&id) {
        Ok(n) => n as i32,
        Err(e) => {
            eprintln!("rterm_available error: {}", e);
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
    let id = cstr(id);
    match pty_manager::resize(&id, cols, rows) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("rterm_resize error: {}", e);
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn rterm_close(id: *const c_char) -> i32 {
    let id = cstr(id);
    match pty_manager::close(&id) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("rterm_close error: {}", e);
            -1
        }
    }
}
