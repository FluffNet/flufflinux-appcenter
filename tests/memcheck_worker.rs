//! Test-only wrapper for the isolated offline Flatpak integration fixtures.
//! Compile with rustc, then use as APPCENTER_TEST_BINARY. Never installed.
use std::{env, os::unix::process::CommandExt, path::Path, process::Command};
fn main() {
    let binary = env::var("APPCENTER_MEMCHECK_BINARY").expect("explicit test binary required");
    let logs = env::var("APPCENTER_MEMCHECK_LOGS").expect("explicit log directory required");
    assert!(Path::new(&binary).is_absolute() && Path::new(&logs).is_dir());
    let args: Vec<_> = env::args().skip(1).collect();
    assert!(matches!(
        args.first().map(String::as_str),
        Some("--updates-worker" | "--transaction-worker" | "--sizes-worker")
    ));
    // Never profile an integration worker against the desktop user's deployment.
    let root = env::var("FLATPAK_USER_DIR").expect("isolated Flatpak installation required");
    assert!(root.starts_with("/tmp/appcenter-") && root.ends_with("/user"));
    let mut checker = Command::new("valgrind");
    if let Ok(root) = env::var("APPCENTER_MEMCHECK_DEBUG_ROOT") {
        checker.arg(format!("--extra-debuginfo-path={root}"));
    }
    // Replace the wrapper: fixture deadlines must kill the actual profiler,
    // not leave it behind as an orphan while loading symbols.
    let error = checker
        .args([
            "--tool=memcheck",
            "--leak-check=full",
            "--show-leak-kinds=definite,indirect",
            "--errors-for-leak-kinds=definite,indirect",
            // GLib/GPG fork helpers inherit snapshots of other threads' heaps.
            // Do not turn their normal exit into a transaction failure. Audit
            // the parent reports explicitly, without custom leak suppressions.
            "--child-silent-after-fork=yes",
            "--num-callers=30",
        ])
        .arg(format!("--log-file={logs}/worker-%p.log"))
        .arg(binary)
        .args(args)
        .exec();
    panic!("start memory checker: {error}");
}
