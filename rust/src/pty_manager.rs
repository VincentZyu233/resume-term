use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize, PtySystem, ChildKiller};

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

pub fn spawn(
    id: &str,
    shell: &str,
    executable: Option<&str>,
    working_dir: Option<&str>,
    args: &[String],
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let pty_system = native_pty_system();
    let size = PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    };

    let mut pair = pty_system.openpty(size).map_err(|e| e.to_string())?;

    let program = executable.unwrap_or(shell);
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

    let child_killer = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    let reader = pair.master.try_reader().map_err(|e| e.to_string())?;
    let writer = pair.master.take_writer().map_err(|e| e.to_string())?;

    let buffer = Arc::new(Mutex::new(Vec::new()));
    let stop = Arc::new(AtomicBool::new(false));

    let buf_clone = buffer.clone();
    let stop_clone = stop.clone();
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        let mut reader = reader;
        loop {
            if stop_clone.load(Ordering::Relaxed) {
                break;
            }
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if let Ok(mut b) = buf_clone.lock() {
                        b.extend_from_slice(&buf[..n]);
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(1));
                    continue;
                }
                Err(_) => break,
            }
        }
    });

    let session = PtySession {
        buffer,
        writer: Arc::new(Mutex::new(writer)),
        stop,
        child_killer: Some(child_killer),
    };

    let mut map = sessions().lock().map_err(|e| e.to_string())?;
    map.insert(id.to_string(), session);

    Ok(())
}

pub fn write_to(id: &str, data: &[u8]) -> Result<usize, String> {
    let map = sessions().lock().map_err(|e| e.to_string())?;
    let session = map.get(id).ok_or_else(|| format!("unknown pty id: {}", id))?;
    let mut writer = session.writer.lock().map_err(|e| e.to_string())?;
    writer.write_all(data).map_err(|e| e.to_string())?;
    Ok(data.len())
}

pub fn read_from(id: &str, buf: &mut [u8]) -> Result<usize, String> {
    let map = sessions().lock().map_err(|e| e.to_string())?;
    let session = map.get(id).ok_or_else(|| format!("unknown pty id: {}", id))?;
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
    let session = map.get(id).ok_or_else(|| format!("unknown pty id: {}", id))?;
    let buffer = session.buffer.lock().map_err(|e| e.to_string())?;
    Ok(buffer.len())
}
