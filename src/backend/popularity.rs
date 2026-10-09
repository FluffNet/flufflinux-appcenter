//! Public bulk popularity counts, never a query containing installed app IDs.
use super::{number, storage, text};
use chrono::{DateTime, Utc};
use serde_json::{json, Map, Value};
use std::{io::Read, time::Duration};
fn valid_id(id: &str) -> bool {
    (3..=255).contains(&id.len())
        && id.contains('.')
        && (id.as_bytes()[0].is_ascii_alphabetic() || id.starts_with('_'))
        && id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'.' | b'-'))
}
fn valid_count(value: &Value) -> bool {
    value
        .as_f64()
        .is_some_and(|n| n.is_finite() && (0.0..=1e12).contains(&n) && n.fract() == 0.0)
}
pub fn valid_counts(raw: &Value) -> Value {
    Value::Object(
        raw.as_object()
            .into_iter()
            .flatten()
            .filter(|(id, count)| valid_id(id) && valid_count(count))
            .map(|(id, count)| (id.clone(), count.clone()))
            .collect(),
    )
}
pub fn cached() -> Value {
    let empty = json!({"state":"idle","counts":{},"fetchedAt":""});
    let Ok(saved) = storage::read_json(
        &storage::cache_dir().join("flathub-popularity.json"),
        1024 * 1024,
    ) else {
        return empty;
    };
    let Some(date) = DateTime::parse_from_rfc3339(text(&saved, "fetchedAt"))
        .ok()
        .filter(|date| *date <= Utc::now())
    else {
        return empty;
    };
    if saved["version"] != 1 {
        return empty;
    }
    let counts = valid_counts(&saved["counts"]);
    if counts.as_object().is_none_or(|v| v.is_empty()) {
        return empty;
    }
    json!({"state":"ready","counts":counts,"fetchedAt":date.to_rfc3339()})
}
pub fn should_load(current: &Value, last_attempt: Option<std::time::Instant>) -> bool {
    if current["state"] == "loading"
        || last_attempt.is_some_and(|time| time.elapsed() < Duration::from_secs(60))
    {
        return false;
    }
    let fresh = DateTime::parse_from_rfc3339(text(current, "fetchedAt"))
        .ok()
        .is_some_and(|date| {
            let age = Utc::now().signed_duration_since(date).num_seconds();
            (0..24 * 3600).contains(&age)
        });
    !fresh
        || current["counts"]
            .as_object()
            .is_none_or(|map| map.is_empty())
}
pub fn page(
    bytes: &[u8],
    page: u64,
    total: &mut u64,
    counts: &mut Map<String, Value>,
) -> Result<(), String> {
    if bytes.len() > 8 * 1024 * 1024 {
        return Err("Popularity response too large".into());
    }
    let data: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    let pages = number(&data, "totalPages");
    let hits = data["hits"].as_array().ok_or("Invalid popularity page")?;
    if number(&data, "page") != page
        || !(1..=20).contains(&pages)
        || page > pages
        || (*total != 0 && *total != pages)
        || number(&data, "hitsPerPage") != 1000
        || hits.len() > 1000
    {
        return Err("Invalid popularity pagination".into());
    }
    *total = pages;
    for row in hits {
        let id = text(row, "app_id");
        if valid_id(id) && valid_count(&row["installs_last_month"]) {
            counts.insert(id.into(), row["installs_last_month"].clone());
        }
    }
    Ok(())
}
pub fn fetch() -> Result<Value, String> {
    let agent = super::http::agent(Duration::from_secs(15));
    let (mut pages, mut current) = (0, 1);
    let mut counts = Map::new();
    loop {
        let url =
            format!("https://flathub.org/api/v2/collection/popular?page={current}&per_page=1000");
        let mut response = agent
            .get(&url)
            .header("Accept", "application/json")
            .header("User-Agent", "FluffLinux-AppCenter/2026.10")
            .call()
            .map_err(|e| e.to_string())?;
        if response.status() != 200 {
            return Err("Could not load popularity".into());
        }
        let mut data = vec![];
        response
            .body_mut()
            .as_reader()
            .take(8 * 1024 * 1024 + 1)
            .read_to_end(&mut data)
            .map_err(|e| e.to_string())?;
        page(&data, current, &mut pages, &mut counts)?;
        if current == pages {
            break;
        }
        current += 1;
    }
    if counts.is_empty() {
        return Err("Empty popularity response".into());
    }
    let date = Utc::now().to_rfc3339();
    let saved = json!({"version":1,"counts":counts,"fetchedAt":date});
    if let Err(error) = storage::write_json(
        &storage::cache_dir().join("flathub-popularity.json"),
        &saved,
    ) {
        eprintln!("Could not save popularity: {error}");
    }
    Ok(json!({"state":"ready","counts":counts,"fetchedAt":date}))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_malformed_counts_and_inconsistent_pages() {
        assert_eq!(
            valid_counts(
                &json!({"org.Test.App":100,"bad":100,"org.Bad.Negative":-1,"org.Bad.Decimal":1.2})
            ),
            json!({"org.Test.App":100})
        );
        let mut total = 0;
        let mut counts = Map::new();
        let first=json!({"page":1,"totalPages":2,"hitsPerPage":1000,"hits":[{"app_id":"org.Test.App","installs_last_month":12}]}).to_string();
        page(first.as_bytes(), 1, &mut total, &mut counts).unwrap();
        assert!(page(
            json!({"page":2,"totalPages":3,"hitsPerPage":1000,"hits":[]})
                .to_string()
                .as_bytes(),
            2,
            &mut total,
            &mut counts
        )
        .is_err());
    }
    #[test]
    fn zero_is_not_missing_and_fresh_counts_do_not_start_network_work() {
        assert_eq!(
            valid_counts(
                &json!({"org.example.Zero":0,"org.example.Good":123,"org.example.Negative":-1,"org.example.Float":1.5,"org.example.Null":null,"org.example.String":"10","../../bad":10})
            ),
            json!({"org.example.Zero":0,"org.example.Good":123})
        );
        let current = json!({"state":"ready","counts":{"org.example.Zero":0},"fetchedAt":Utc::now().to_rfc3339()});
        assert!(!should_load(&current, None));
        assert!(!should_load(&json!({"state":"loading"}), None));
        assert!(!should_load(
            &json!({"state":"unavailable"}),
            Some(std::time::Instant::now())
        ));
        let mut count = Map::new();
        let mut total = 0;
        for invalid in [
            b"<html>offline</html>".to_vec(),
            vec![b' '; 8 * 1024 * 1024 + 1],
            json!({"page":1,"totalPages":999,"hitsPerPage":1000,"hits":[]})
                .to_string()
                .into_bytes(),
        ] {
            assert!(page(&invalid, 1, &mut total, &mut count).is_err());
        }
        let good=json!({"page":1,"totalPages":1,"hitsPerPage":1000,"hits":[{"app_id":"org.example.Zero","installs_last_month":0}]}).to_string();
        page(good.as_bytes(), 1, &mut total, &mut count).unwrap();
        assert_eq!(count["org.example.Zero"], 0);
        assert!(page(good.as_bytes(), 2, &mut total, &mut count).is_err());
    }
}
