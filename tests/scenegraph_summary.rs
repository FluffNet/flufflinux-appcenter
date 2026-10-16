//! Read Qt's text .qtd profiler export without additional dependencies.
//! rustc tests/scenegraph_summary.rs -o target/scenegraph-summary
//! target/scenegraph-summary trace.qtd [start_seconds] [end_seconds]
use std::{
    collections::BTreeMap,
    env, fs,
    io::{BufRead, BufReader},
};
fn attr<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    line.split_once(&format!("{key}=\""))?
        .1
        .split_once('"')
        .map(|v| v.0)
}
fn main() {
    let args: Vec<_> = env::args().collect();
    let start = args
        .get(2)
        .map(|s| s.parse::<f64>().unwrap() * 1e9)
        .unwrap_or(0.0) as i64;
    let end = args
        .get(3)
        .map(|s| s.parse::<f64>().unwrap() * 1e9)
        .unwrap_or(i64::MAX as f64) as i64;
    let mut index = 0;
    let mut types = BTreeMap::new();
    let mut timings: BTreeMap<(usize, usize), Vec<(i64, i64)>> = BTreeMap::new();
    for line in BufReader::new(fs::File::open(&args[1]).unwrap()).lines() {
        let line = line.unwrap();
        if line.contains("<event index=") {
            index = attr(&line, "index").unwrap().parse::<usize>().unwrap();
        } else if let Some((_, value)) = line.split_once("<sgEventType>") {
            types.insert(
                index,
                value.split('<').next().unwrap().parse::<usize>().unwrap(),
            );
        } else if line.contains("<range ") {
            let Some(kind) = attr(&line, "eventIndex")
                .and_then(|s| s.parse().ok())
                .and_then(|i| types.get(&i))
            else {
                continue;
            };
            let at = attr(&line, "startTime").unwrap().parse::<i64>().unwrap();
            if at < start || at > end {
                continue;
            }
            for stage in 1..=5 {
                if let Some(value) =
                    attr(&line, &format!("timing{stage}")).and_then(|s| s.parse::<i64>().ok())
                {
                    if value >= 0 {
                        timings.entry((*kind, stage)).or_default().push((value, at));
                    }
                }
            }
        }
    }
    for ((kind, stage), mut values) in timings {
        values.sort_unstable();
        let label = match (kind, stage) {
            (3, 1) => "render-thread sync",
            (3, 2) => "render-thread render",
            (3, 3) => "render-thread swap",
            (6, 1) => "GUI polish",
            (6, 2) => "GUI wait",
            (6, 3) => "GUI sync",
            (6, 4) => "GUI animations",
            _ => "other",
        };
        let n = values.len();
        let max = values[n - 1];
        println!("type={kind} stage={stage} {label} count={n} p50={:.3} p95={:.3} p99={:.3} max={:.3}ms at={:.3}s", values[n/2].0 as f64/1e6, values[n*95/100].0 as f64/1e6, values[n*99/100].0 as f64/1e6, max.0 as f64/1e6, max.1 as f64/1e9);
    }
}
