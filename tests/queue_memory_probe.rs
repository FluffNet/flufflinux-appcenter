//! Isolated QML fixture measurement, not part of the installed application.
//! Run: rustc tests/queue_memory_probe.rs -o target/queue-memory-probe
//! Then: target/queue-memory-probe /usr/lib/qt6/bin/qmltestrunner -input ...
use std::{
    collections::BTreeMap,
    env, fs,
    process::Command,
    thread,
    time::{Duration, Instant},
};

fn thread_ticks(pid: u32) -> BTreeMap<String, (u64, String, String)> {
    let mut result = BTreeMap::new();
    for entry in fs::read_dir(format!("/proc/{pid}/task"))
        .into_iter()
        .flatten()
        .flatten()
    {
        let stat = fs::read_to_string(entry.path().join("stat")).unwrap_or_default();
        let Some((name, fields)) = stat.rsplit_once(") ") else {
            continue;
        };
        let fields: Vec<_> = fields.split_whitespace().collect();
        if fields.len() < 37 {
            continue;
        }
        let ticks = fields[11].parse::<u64>().unwrap_or(0) + fields[12].parse::<u64>().unwrap_or(0);
        result.insert(
            entry.file_name().to_string_lossy().into(),
            (
                ticks,
                name.split_once('(').unwrap().1.into(),
                fields[36].into(),
            ),
        );
    }
    result
}

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

fn proportional_kib(pid: u32) -> u64 {
    // RSS sums count fork/shared pages repeatedly. PSS apportions them across
    // mappings. This is not an atomic process-tree snapshot: fork/exit during
    // traversal can still transiently overcount, so require sustained excess.
    let own = fs::read_to_string(format!("/proc/{pid}/smaps_rollup"))
        .unwrap_or_default()
        .lines()
        .find(|line| line.starts_with("Pss:"))
        .and_then(|line| line.split_whitespace().nth(1)?.parse::<u64>().ok())
        .unwrap_or(0);
    let children =
        fs::read_to_string(format!("/proc/{pid}/task/{pid}/children")).unwrap_or_default();
    own + children
        .split_whitespace()
        .filter_map(|pid| pid.parse().ok())
        .map(proportional_kib)
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
    // A bounded override permits measuring a failing baseline to completion.
    // Normal regression runs keep the requested decimal 1 GB budget.
    let budget = env::var("APPCENTER_TEST_MEMORY_BYTES")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(1_000_000_000)
        .clamp(64_000_000, 1_500_000_000);
    let mut peak_kib = 0;
    let mut peak_tree_kib = 0;
    let mut peak_pss_kib = 0;
    let mut pss_over_budget = 0;
    let mut measured_pss = Instant::now();
    let mut reported = Instant::now();
    let mut previous_threads = BTreeMap::new();
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
        if measured_pss.elapsed() >= Duration::from_millis(100) {
            let pss = proportional_kib(child.id());
            peak_pss_kib = peak_pss_kib.max(pss);
            pss_over_budget = if pss * 1024 >= budget {
                pss_over_budget + 1
            } else {
                0
            };
            measured_pss = Instant::now();
        }
        if reported.elapsed() >= Duration::from_secs(5) {
            println!(
                "QUEUE_MEMORY_SAMPLE elapsedMs={} treeKiB={tree_kib}",
                started.elapsed().as_millis()
            );
            let threads = thread_ticks(child.id());
            let mut busy: Vec<_> = threads
                .iter()
                .map(|(tid, (ticks, name, core))| {
                    let previous = previous_threads.get(tid).copied().unwrap_or(0);
                    (ticks.saturating_sub(previous), tid, name, core)
                })
                .collect();
            busy.sort_by_key(|entry| std::cmp::Reverse(entry.0));
            for (ticks, tid, name, core) in busy.into_iter().take(5) {
                println!("QUEUE_CPU elapsedMs={} intervalMs={} tid={tid} ticks={ticks} core={core} name={name}", started.elapsed().as_millis(), reported.elapsed().as_millis());
            }
            previous_threads = threads
                .into_iter()
                .map(|(tid, (ticks, _, _))| (tid, ticks))
                .collect();
            let rollup = fs::read_to_string(format!("/proc/{}/smaps_rollup", child.id()))
                .unwrap_or_default();
            println!(
                "QUEUE_RESIDENT {}",
                rollup
                    .lines()
                    .filter(|line| line.starts_with("Rss:")
                        || line.starts_with("Pss:")
                        || line.starts_with("Private_Dirty:"))
                    .collect::<Vec<_>>()
                    .join(" ")
            );
            reported = Instant::now();
        }
        if peak_kib * 1024 >= budget
            || pss_over_budget >= 3
            || started.elapsed() > Duration::from_secs(timeout)
        {
            child.kill().expect("stop test exceeding budget");
            child.wait().unwrap();
            panic!("fixture exceeded memory/time budget: peak {peak_kib} KiB, peak tree RSS {peak_tree_kib} KiB, peak tree PSS {peak_pss_kib} KiB, elapsed {} ms", started.elapsed().as_millis());
        }
        if let Some(status) = child.try_wait().unwrap() {
            println!("QUEUE_MEMORY peakKiB={peak_kib} peakTreeKiB={peak_tree_kib} peakPssKiB={peak_pss_kib} elapsedMs={} exitCode={}", started.elapsed().as_millis(), status.code().unwrap_or(1));
            std::process::exit(status.code().unwrap_or(1));
        }
        thread::sleep(Duration::from_millis(10));
    }
}
