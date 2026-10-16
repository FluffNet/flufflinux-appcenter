//! Bounded native subprocesses. No shell expansion or inherited input stream.
use gio::prelude::*;
use std::{
    io::Read,
    os::unix::process::CommandExt,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

#[derive(Debug)]
pub struct Output {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: String,
}
pub fn parent_death_signal() -> Result<(), String> {
    // Worker lifetime is tied to its GUI/service parent, including forced exit.
    if unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) } != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    if unsafe { libc::getppid() } == 1 {
        return Err("The parent process has closed".into());
    }
    Ok(())
}
pub fn run(
    mut command: Command,
    timeout: Duration,
    limit: usize,
    cancel: Option<&gio::Cancellable>,
) -> Result<Output, String> {
    if cancel.is_some_and(|c| c.is_cancelled()) {
        return Err("Cancelled".into());
    }
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // Separate only this child's process group, so cancellation cannot hit the GUI.
    unsafe {
        command.pre_exec(|| {
            if libc::setpgid(0, 0) != 0 || libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            if libc::getppid() == 1 {
                return Err(std::io::Error::other("Parent closed"));
            }
            Ok(())
        });
    }
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let output = std::thread::spawn(move || {
        let mut data = Vec::new();
        stdout
            .take(limit as u64 + 1)
            .read_to_end(&mut data)
            .map(|_| data)
    });
    let diagnostics = std::thread::spawn(move || {
        let mut data = Vec::new();
        stderr
            .take(64 * 1024 + 1)
            .read_to_end(&mut data)
            .map(|_| data)
    });
    let start = Instant::now();
    let mut timed_out = false;
    let status = loop {
        if cancel.is_some_and(|c| c.is_cancelled()) || start.elapsed() >= timeout {
            timed_out = true;
            unsafe {
                libc::kill(-(child.id() as i32), libc::SIGKILL);
            }
            break child.wait();
        }
        match child.try_wait() {
            Ok(Some(status)) => break Ok(status),
            Ok(None) => std::thread::sleep(Duration::from_millis(20)),
            Err(e) => break Err(e),
        }
    };
    // Descendants must not retain pipes after their command exits.
    unsafe {
        libc::kill(-(child.id() as i32), libc::SIGKILL);
    }
    let stdout = output
        .join()
        .map_err(|_| "Output reader failed")?
        .map_err(|e| e.to_string())?;
    let stderr = diagnostics
        .join()
        .map_err(|_| "Error reader failed")?
        .map_err(|e| e.to_string())?;
    if timed_out {
        return Err(if cancel.is_some_and(|c| c.is_cancelled()) {
            "Cancelled"
        } else {
            "The operation timed out"
        }
        .into());
    }
    if stdout.len() > limit || stderr.len() > 64 * 1024 {
        return Err("The subprocess response was too large".into());
    }
    Ok(Output {
        code: status.map_err(|e| e.to_string())?.code().unwrap_or(-1),
        stdout,
        stderr: String::from_utf8_lossy(&stderr).trim().into(),
    })
}
pub fn flatpak(
    args: &[&str],
    timeout: u64,
    cancel: Option<&gio::Cancellable>,
) -> Result<Output, String> {
    let mut command = Command::new("/usr/bin/flatpak");
    command.args(args);
    run(
        command,
        Duration::from_secs(timeout),
        16 * 1024 * 1024,
        cancel,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn subprocess_is_bounded_and_reaped() {
        let mut command = Command::new("/usr/bin/sleep");
        command.arg("5");
        assert!(run(command, Duration::from_millis(50), 1024, None)
            .unwrap_err()
            .contains("timed out"));
    }
}
