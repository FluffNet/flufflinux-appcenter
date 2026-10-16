use flufflinux_appcenter::backend::storage;
use serde_json::json;
use std::{
    io::{BufRead, BufReader, Write},
    process::{Command, Stdio},
    time::Duration,
};

// Runs only in an explicitly spawned test process, not the application binary.
#[test]
fn writer_child() {
    let Some(path) = std::env::var_os("APPCENTER_CACHE_TEST_CHILD") else {
        return;
    };
    let path = std::path::PathBuf::from(path);
    let _lock = storage::FileLock::acquire(&path.with_extension("lock")).unwrap();
    let apps:Vec<_>=(0..2000).map(|i|json!({"id":format!("org.example.Test{i}"),"name":format!("App {i}"),"description":"fixture ".repeat(64)})).collect();
    println!("writer-ready");
    std::io::stdout().flush().unwrap();
    loop {
        storage::write_cache(&path, "fixture", &apps, chrono::Utc::now()).unwrap();
    }
}

#[test]
fn killed_writer_and_immediate_reopen_never_observe_a_partial_cache() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("catalog.json");
    storage::write_cache(
        &path,
        "fixture",
        &[json!({"id":"org.example.Old","name":"Old"})],
        chrono::Utc::now(),
    )
    .unwrap();
    for delay in [0, 2, 10, 30] {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "writer_child", "--nocapture"])
            .env("APPCENTER_CACHE_TEST_CHILD", &path)
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let reader = BufReader::new(child.stdout.take().unwrap());
        let ready = reader
            .lines()
            .any(|line| line.unwrap().contains("writer-ready"));
        assert!(ready);
        // A reopening frontend may read concurrently with serialization/fsync.
        for _ in 0..3 {
            let snapshot = storage::read_cache(&path, "fixture", chrono::Utc::now()).unwrap();
            assert!([1, 2000].contains(&snapshot.apps.len()));
        }
        std::thread::sleep(Duration::from_millis(delay));
        child.kill().unwrap();
        child.wait().unwrap();
        assert!(storage::read_cache(&path, "fixture", chrono::Utc::now()).is_some());
        // Kernel-owned locks do not survive termination, even during a save.
        assert!(storage::FileLock::acquire(&path.with_extension("lock")).is_ok());
    }
}

#[test]
fn invalid_and_unwritable_destinations_preserve_the_previous_cache() {
    use std::os::unix::fs::PermissionsExt;
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("catalog.json");
    let now = chrono::Utc::now();
    let apps = [json!({"id":"org.example.App","name":"App"})];
    storage::write_cache(&path, "fixture", &apps, now).unwrap();
    let before = std::fs::read(&path).unwrap();
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o500)).unwrap();
    let result = storage::write_cache(&path, "changed", &[], now);
    std::fs::set_permissions(temp.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    assert!(result.is_err());
    assert_eq!(std::fs::read(&path).unwrap(), before);
    assert!(storage::write_cache(&path.join("impossible"), "fixture", &apps, now).is_err());
    assert!(storage::read_cache(&path, "fixture", now - chrono::Duration::seconds(1)).is_none());
    let stale = storage::read_cache(&path, "fixture", now + chrono::Duration::days(2)).unwrap();
    assert!(!storage::fresh(
        stale.saved_at,
        now + chrono::Duration::days(2)
    ));
    let file = std::fs::File::create(&path).unwrap();
    file.set_len(storage::CACHE_LIMIT + 1).unwrap();
    assert!(storage::read_cache(&path, "fixture", now).is_none());
}

#[test]
fn a_fifo_is_not_a_cache_and_never_blocks_startup() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("catalog.json");
    let name = std::ffi::CString::new(path.as_os_str().as_encoded_bytes()).unwrap();
    assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
    let start = std::time::Instant::now();
    assert!(storage::read_cache(&path, "fixture", chrono::Utc::now()).is_none());
    assert!(start.elapsed() < Duration::from_millis(200));
}
