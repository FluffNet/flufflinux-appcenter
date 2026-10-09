use flufflinux_appcenter::backend::{recovery, storage};
use serde_json::json;
use std::{
    io::{BufRead, BufReader, Write},
    process::{Command, Stdio},
    time::Duration,
};

fn record(id: usize) -> serde_json::Value {
    json!({"recoveryId":format!("test:{id}"),"action":"install","installation":"user","id":format!("org.example.Test{id}"),"name":format!("Test {id}"),"operations":[]})
}
#[test]
fn queue_writer_child() {
    let Some(path) = std::env::var_os("APPCENTER_QUEUE_TEST_CHILD") else {
        return;
    };
    let path = std::path::PathBuf::from(path);
    let records: Vec<_> = (0..400).map(record).collect();
    println!("writer-ready");
    std::io::stdout().flush().unwrap();
    loop {
        recovery::save(&path, &records).unwrap();
    }
}
#[test]
fn forced_termination_and_immediate_reopen_keep_a_complete_journal() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("queue.json");
    recovery::save(&path, &[record(0)]).unwrap();
    for delay in [0, 1, 5, 15] {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "queue_writer_child", "--nocapture"])
            .env("APPCENTER_QUEUE_TEST_CHILD", &path)
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        assert!(BufReader::new(child.stdout.take().unwrap())
            .lines()
            .any(|line| line.unwrap().contains("writer-ready")));
        std::thread::sleep(Duration::from_millis(delay));
        child.kill().unwrap();
        child.wait().unwrap();
        assert!([1, 400].contains(&recovery::load(&path).unwrap().len()));
        assert!(storage::FileLock::acquire(&path.with_extension("lock")).is_ok());
        // An orphan temporary file must never replace the last valid journal.
        std::fs::write(temp.path().join(".queue.json.orphan.tmp"), b"{broken").unwrap();
        assert!(!recovery::load(&path).unwrap().is_empty());
    }
}
#[test]
fn failed_save_preserves_existing_data_and_fifo_reads_do_not_hang() {
    use std::os::unix::{ffi::OsStrExt, fs::PermissionsExt};
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("queue.json");
    recovery::save(&path, &[record(0)]).unwrap();
    let before = std::fs::read(&path).unwrap();
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o500)).unwrap();
    let failed = recovery::save(&path, &[record(1)]);
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    assert!(failed.is_err());
    assert_eq!(std::fs::read(&path).unwrap(), before);
    let fifo = temp.path().join("fifo");
    let name = std::ffi::CString::new(fifo.as_os_str().as_bytes()).unwrap();
    assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
    assert!(recovery::load(&fifo).is_err());
}

#[test]
fn real_journal_worker_uses_stdin_and_reports_bad_data_without_truncating() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("queue with spaces.json");
    let run = |data: &[u8]| {
        let mut worker = Command::new(env!("CARGO_BIN_EXE_flufflinux-appcenter"))
            .args(["--recovery-worker", "save"])
            .arg(&path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        worker.stdin.take().unwrap().write_all(data).unwrap();
        let output = worker.wait_with_output().unwrap();
        assert!(output.status.success());
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap()
    };
    assert_eq!(
        run(serde_json::to_string(&vec![record(0)]).unwrap().as_bytes())["ok"],
        true
    );
    let before = std::fs::read(&path).unwrap();
    assert_eq!(run(b"{interrupted")["ok"], false);
    assert_eq!(std::fs::read(&path).unwrap(), before);
}
