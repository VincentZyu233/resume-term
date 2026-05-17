use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use portable_pty::{native_pty_system, CommandBuilder, PtySize, ChildKiller};

use crate::logger;

pub struct PtySession {
    pub buffer: Arc<Mutex<Vec<u8>>>,
    pub writer: Arc<Mutex<Box<dyn Write + Send>>>,
    pub stop: Arc<AtomicBool>,
    #[allow(dead_code)]
    pub child_killer: Option<Box<dyn ChildKiller + Send>>,
}

fn sessions() -> &'static Mutex<HashMap<String, PtySession>> {
    static SESSIONS: std::sync::OnceLock<Mutex<HashMap<String, PtySession>>> =
        std::sync::OnceLock::new();
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

struct SpawnResult {
    reader: Box<dyn Read + Send>,
    writer: Box<dyn Write + Send>,
    child_killer: Box<dyn ChildKiller + Send>,
}

fn try_spawn(
    program: &str,
    working_dir: Option<&str>,
    args: &[String],
    cols: u16,
    rows: u16,
) -> Result<SpawnResult, String> {
    logger::log_info(&format!("try_spawn: program={}, wd={:?}, cols={}, rows={}", program, working_dir, cols, rows));
    let pty_system = native_pty_system();
    let size = PtySize { rows, cols, pixel_width: 0, pixel_height: 0 };

    let mut pair = pty_system.openpty(size).map_err(|e| {
        let msg = format!("openpty failed: {}", e);
        logger::log_error(&msg);
        msg
    })?;
    logger::log_info("openpty OK");

    let mut cmd = CommandBuilder::new(program);
    for arg in args {
        cmd.arg(arg);
    }
    if let Some(wd) = working_dir {
        if !wd.is_empty() {
            cmd.cwd(wd);
        }
    }
    cmd.env("TERM", "xterm-256color");

    let child_killer = pair.slave.spawn_command(cmd).map_err(|e| {
        let msg = format!("spawn_command failed for '{}': {}", program, e);
        logger::log_error(&msg);
        msg
    })?;
    logger::log_info(&format!("spawn_command OK for '{}'", program));

    let reader = pair.master.try_clone_reader().map_err(|e| {
        let msg = format!("try_clone_reader failed: {}", e);
        logger::log_error(&msg);
        msg
    })?;
    logger::log_info("try_clone_reader OK");

    let writer = pair.master.take_writer().map_err(|e| {
        let msg = format!("take_writer failed: {}", e);
        logger::log_error(&msg);
        msg
    })?;
    logger::log_info("take_writer OK");

    Ok(SpawnResult { reader, writer, child_killer })
}

pub fn spawn(
    id: &str,
    shell: &str,
    executable: Option<&str>,
    working_dir: Option<&str>,
    args: &[String],
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let primary = executable.unwrap_or(shell);
    logger::log_info(&format!("spawn: id={}, primary={}, wd={:?}, args={:?}", id, primary, working_dir, args));

    let candidates: Vec<&str> = if cfg!(target_os = "windows") {
        vec![primary, "powershell", "cmd"]
    } else {
        vec![primary, "bash", "sh"]
    };

    let mut seen = HashSet::new();
    let mut last_err = String::new();

    for &prog in &candidates {
        if !seen.insert(prog) {
            continue;
        }
        logger::log_info(&format!("spawn: trying candidate '{}'", prog));
        match try_spawn(prog, working_dir, args, cols, rows) {
            Ok(result) => {
                logger::log_info(&format!("spawn: candidate '{}' succeeded, starting reader thread", prog));
                let buffer = Arc::new(Mutex::new(Vec::new()));
                let stop = Arc::new(AtomicBool::new(false));

                let buf_clone = buffer.clone();
                let stop_clone = stop.clone();
                let thread_id = id.to_string();
                thread::spawn(move || {
                    let mut buf = [0u8; 8192];
                    let mut reader = result.reader;
                    let mut total_read: usize = 0;
                    logger::log_info(&format!("reader_thread STARTED: id={}", thread_id));
                    loop {
                        if stop_clone.load(Ordering::Relaxed) {
                            logger::log_info(&format!("reader_thread STOPPED: id={}", thread_id));
                            break;
                        }
                        match reader.read(&mut buf) {
                            Ok(0) => {
                                logger::log_info(&format!("reader_thread EOF: id={}, total_read={}", thread_id, total_read));
                                break;
                            }
                            Ok(n) => {
                                total_read += n;
                                if let Ok(mut b) = buf_clone.lock() {
                                    b.extend_from_slice(&buf[..n]);
                                }
                                // Only log periodically to avoid flooding
                                if total_read % 4096 < n {
                                    logger::log_info(&format!("reader_thread DATA: id={}, chunk={}, total={}", thread_id, n, total_read));
                                }
                            }
                            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                                thread::sleep(Duration::from_millis(1));
                                continue;
                            }
                            Err(e) => {
                                logger::log_error(&format!("reader_thread ERROR: id={}, err={}", thread_id, e));
                                break;
                            }
                        }
                    }
                    logger::log_info(&format!("reader_thread EXITED: id={}, total_read={}", thread_id, total_read));
                });

                let session = PtySession {
                    buffer,
                    writer: Arc::new(Mutex::new(result.writer)),
                    stop,
                    child_killer: Some(result.child_killer),
                };

                let mut map = sessions().lock().map_err(|e| e.to_string())?;
                map.insert(id.to_string(), session);
                logger::log_info(&format!("spawn COMPLETE: id={}", id));
                return Ok(());
            }
            Err(e) => {
                logger::log_error(&format!("spawn: candidate '{}' failed: {}", prog, e));
                last_err = e;
                continue;
            }
        }
    }

    let msg = format!("Failed to spawn. Tried: {}. Last error: {}", candidates.join(", "), last_err);
    logger::log_error(&msg);
    Err(msg)
}

pub fn write_to(id: &str, data: &[u8]) -> Result<usize, String> {
    let map = sessions().lock().map_err(|e| e.to_string())?;
    let session = map.get(id).ok_or_else(|| {
        let msg = format!("write_to: unknown pty id: {}", id);
        logger::log_error(&msg);
        msg
    })?;
    let mut writer = session.writer.lock().map_err(|e| e.to_string())?;
    writer.write_all(data).map_err(|e| {
        let msg = format!("write_to write failed: id={}, err={}", id, e);
        logger::log_error(&msg);
        msg
    })?;
    Ok(data.len())
}

pub fn read_from(id: &str, buf: &mut [u8]) -> Result<usize, String> {
    let map = sessions().lock().map_err(|e| e.to_string())?;
    let session = map.get(id).ok_or_else(|| {
        let msg = format!("read_from: unknown pty id: {}", id);
        logger::log_error(&msg);
        msg
    })?;
    let mut buffer = session.buffer.lock().map_err(|e| e.to_string())?;
    let available = buffer.len().min(buf.len());
    if available > 0 {
        buf[..available].copy_from_slice(&buffer[..available]);
        buffer.drain(..available);
    }
    Ok(available)
}

pub fn resize(_id: &str, _cols: u16, _rows: u16) -> Result<(), String> {
    Ok(())
}

pub fn close(id: &str) -> Result<(), String> {
    let mut map = sessions().lock().map_err(|e| e.to_string())?;
    if let Some(session) = map.remove(id) {
        session.stop.store(true, Ordering::Relaxed);
    }
    Ok(())
}

pub fn available(id: &str) -> Result<usize, String> {
    let map = sessions().lock().map_err(|e| e.to_string())?;
    let session = map.get(id).ok_or_else(|| {
        let msg = format!("available: unknown pty id: {}", id);
        logger::log_error(&msg);
        msg
    })?;
    let buffer = session.buffer.lock().map_err(|e| e.to_string())?;
    let len = buffer.len();
    if len > 0 {
        logger::log_info(&format!("available: id={}, bytes={}", id, len));
    }
    Ok(len)
}
