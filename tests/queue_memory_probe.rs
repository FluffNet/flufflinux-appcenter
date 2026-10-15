//! Isolated QML fixture measurement, not part of the installed application.
//! Run: rustc tests/queue_memory_probe.rs -o target/queue-memory-probe
//! Then: target/queue-memory-probe /usr/lib/qt6/bin/qmltestrunner -input ...
use std::{
    env, fs,
    process::Command,
    thread,
    time::{Duration, Instant},
};

fn resident_kib(pid: u32) -> u64 {
    let own = fs::read_to_string(format!("/proc/{pid}/status"))
        .unwrap_or_default()
        .lines()
        .find(|line| line.starts_with("VmRSS:"))
        .and_then(|line| line.split_whitespace().nth(1)?.parse::<u64>().ok())
        .unwrap_or(0);
    let children =
        fs::read_to_string(format!("/proc/{pid}/task/{pid}/children")).unwrap_or_default();
    own + children
        .split_whitespace()
        .filter_map(|pid| pid.parse().ok())
        .map(resident_kib)
        .sum::<u64>()
}

fn main() {
    let mut args = env::args().skip(1);
    let program = args.next().expect("test program required");
    let mut child = Command::new(program)
        .args(args)
        .spawn()
        .expect("start test");
    let started = Instant::now();
    let timeout = env::var("APPCENTER_TEST_TIMEOUT_SECONDS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(120)
        .clamp(1, 600);
    let mut peak_kib = 0;
    let mut peak_tree_kib = 0;
    let mut reported = Instant::now();
    loop {
        if let Ok(status) = fs::read_to_string(format!("/proc/{}/status", child.id())) {
            for line in status.lines().filter(|line| line.starts_with("VmHWM:")) {
                peak_kib = peak_kib.max(
                    line.split_whitespace()
                        .nth(1)
                        .unwrap()
                        .parse::<u64>()
                        .unwrap(),
                );
            }
        }
        let tree_kib = resident_kib(child.id());
        peak_tree_kib = peak_tree_kib.max(tree_kib);
        if reported.elapsed() >= Duration::from_secs(5) {
            println!(
                "QUEUE_MEMORY_SAMPLE elapsedMs={} treeKiB={tree_kib}",
                started.elapsed().as_millis()
            );
            reported = Instant::now();
        }
        if peak_kib * 1024 >= 1_000_000_000
            || tree_kib * 1024 >= 1_000_000_000
            || started.elapsed() > Duration::from_secs(timeout)
        {
            child.kill().expect("stop test exceeding budget");
            child.wait().unwrap();
            panic!("fixture exceeded memory/time budget: peak {} KiB", peak_kib);
        }
        if let Some(status) = child.try_wait().unwrap() {
            println!("QUEUE_MEMORY peakKiB={peak_kib} peakTreeKiB={peak_tree_kib} elapsedMs={} exitCode={}", started.elapsed().as_millis(), status.code().unwrap_or(1));
            std::process::exit(status.code().unwrap_or(1));
        }
        thread::sleep(Duration::from_millis(10));
    }
}
