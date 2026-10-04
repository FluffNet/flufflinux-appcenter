//! Application policy and state belong here, not in the Qt presentation adapter.
pub mod addons;
pub mod background;
pub mod catalog;
pub mod ffi;
mod http;
pub mod locale;
pub mod manager;
pub mod permissions;
pub mod popularity;
pub mod preferences;
pub mod process;
pub mod progress;
pub mod repositories;
pub mod sizes;
pub mod source_removal;
pub mod sources;
pub mod storage;
pub mod transaction;
pub mod updates;

use serde_json::Value;
pub fn text<'a>(value: &'a Value, key: &str) -> &'a str {
    value[key].as_str().unwrap_or("")
}
pub fn flag(value: &Value, key: &str) -> bool {
    value[key].as_bool().unwrap_or(false)
}
pub fn number(value: &Value, key: &str) -> u64 {
    value[key]
        .as_u64()
        .or_else(|| {
            value[key]
                .as_f64()
                .filter(|n| n.is_finite() && *n >= 0.0)
                .map(|n| n as u64)
        })
        .unwrap_or(0)
}
pub fn rows(value: &Value) -> &[Value] {
    value.as_array().map(Vec::as_slice).unwrap_or(&[])
}
pub fn normalized_id(id: &str) -> &str {
    id.strip_suffix(".desktop").unwrap_or(id)
}
pub fn bytes(value: u64) -> String {
    let (divisor, unit) = if value >= 1073741824 {
        (1073741824.0, "GiB")
    } else {
        (1048576.0, "MiB")
    };
    format!("{} {unit}", locale::decimal(value as f64 / divisor))
}
pub fn valid_id(id: &str) -> bool {
    id.len() <= 255
        && id.split('.').count() >= 3
        && id.split('.').enumerate().all(|(index, part)| {
            !part.is_empty()
                && part
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
                && (index != 0 || part.as_bytes()[0].is_ascii_alphabetic() || part.starts_with('_'))
        })
}
pub fn network_state(state: u32, connectivity: u32) -> &'static str {
    match state {
        10 | 20 => "offline",
        30 | 40 => "connecting",
        50 => "local",
        60 | 70 if connectivity == 2 => "portal",
        60 => "limited",
        70 if connectivity == 3 => "limited",
        70 => "online",
        _ => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn lan_is_not_offline() {
        assert_eq!(network_state(50, 1), "local");
        assert_eq!(network_state(60, 3), "limited");
        assert_eq!(network_state(70, 2), "portal");
        assert_eq!(network_state(20, 1), "offline");
        assert_eq!(network_state(0, 0), "unknown");
    }
    #[test]
    fn sizes_are_binary() {
        assert_eq!(bytes(1024 * 1024), "1.00 MiB");
    }
}
