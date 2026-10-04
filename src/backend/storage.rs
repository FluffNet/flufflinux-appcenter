//! Bounded, atomic persistence. A failed or interrupted save never truncates
//! the previous cache; only a successful metadata refresh renews its lifetime.
use super::text;
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

pub const CACHE_LIFETIME: i64 = 12 * 3600;
pub const CACHE_LIMIT: u64 = 64 * 1024 * 1024;
const CACHE_VERSION: u32 = 3;
static SEQUENCE: AtomicU64 = AtomicU64::new(0);

pub fn xdg(variable: &str, fallback: &str) -> PathBuf {
    std::env::var_os(variable)
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(fallback)
        })
}
pub fn cache_dir() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache").join("FluffNet LLC/flufflinux-appcenter")
}
pub fn data_dir() -> PathBuf {
    xdg("XDG_DATA_HOME", ".local/share").join("FluffNet LLC/flufflinux-appcenter")
}
pub fn config_path() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config").join("flufflinux-appcenter.conf")
}
pub fn checksum(value: &Value) -> String {
    format!("{:x}", Sha256::digest(value.to_string().as_bytes()))
}
pub fn read_json(path: &Path, limit: u64) -> io::Result<Value> {
    // A corrupt cache path replaced by a FIFO must not block the GUI at open.
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(path)?;
    if !file.metadata()?.is_file() || file.metadata()?.len() > limit {
        return Err(io::Error::other("File too large"));
    }
    let mut content = Vec::new();
    file.take(limit + 1).read_to_end(&mut content)?;
    if content.len() as u64 > limit {
        return Err(io::Error::other("File too large"));
    }
    serde_json::from_slice(&content).map_err(io::Error::other)
}
pub fn atomic_write(path: &Path, data: &[u8]) -> io::Result<()> {
    let directory = path
        .parent()
        .ok_or_else(|| io::Error::other("Missing parent directory"))?;
    fs::create_dir_all(directory)?;
    let name = path
        .file_name()
        .ok_or_else(|| io::Error::other("Missing filename"))?
        .to_string_lossy();
    let temporary = directory.join(format!(
        ".{name}.{}-{}.tmp",
        std::process::id(),
        SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temporary)?;
        file.write_all(data)?;
        file.sync_all()?;
        fs::rename(&temporary, path)?;
        File::open(directory)?.sync_all()
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}
pub fn write_json(path: &Path, value: &Value) -> io::Result<()> {
    atomic_write(path, value.to_string().as_bytes())
}

pub struct FileLock(File);
impl FileLock {
    pub fn acquire(path: &Path) -> io::Result<Self> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(path)?;
        // flock is released by the kernel on exit, including a killed worker.
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self(file))
    }
}
impl Drop for FileLock {
    fn drop(&mut self) {
        unsafe {
            libc::flock(self.0.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

#[derive(Clone, Debug)]
pub struct Snapshot {
    pub apps: Vec<Value>,
    pub saved_at: DateTime<Utc>,
}
pub fn fresh(saved: DateTime<Utc>, now: DateTime<Utc>) -> bool {
    let age = now.signed_duration_since(saved).num_seconds();
    (0..CACHE_LIFETIME).contains(&age)
}
pub fn read_cache(path: &Path, fingerprint: &str, now: DateTime<Utc>) -> Option<Snapshot> {
    let mut document = read_json(path, CACHE_LIMIT).ok()?;
    let expected = text(&document, "checksum").to_owned();
    document.as_object_mut()?.remove("checksum");
    let saved_at = DateTime::parse_from_rfc3339(text(&document, "savedAt"))
        .ok()?
        .with_timezone(&Utc);
    if document["version"] != CACHE_VERSION
        || text(&document, "fingerprint") != fingerprint
        || fingerprint.is_empty()
        || checksum(&document) != expected
        || saved_at > now
    {
        return None;
    }
    let apps = document["apps"].as_array()?;
    if apps
        .iter()
        .any(|app| text(app, "id").is_empty() || text(app, "name").is_empty())
    {
        return None;
    }
    Some(Snapshot {
        apps: apps.clone(),
        saved_at,
    })
}
pub fn write_cache(
    path: &Path,
    fingerprint: &str,
    apps: &[Value],
    saved_at: DateTime<Utc>,
) -> io::Result<()> {
    if fingerprint.is_empty() {
        return Err(io::Error::other("Unstable source inputs"));
    }
    let mut document = json!({"version":CACHE_VERSION,"fingerprint":fingerprint,"savedAt":saved_at.to_rfc3339(),"apps":apps});
    document["checksum"] = checksum(&document).into();
    let content = document.to_string();
    if content.len() as u64 > CACHE_LIMIT {
        return Err(io::Error::other("Application list too large"));
    }
    write_json(path, &document)
}
pub fn history_date(path: &Path, scope: &str, reference: &str) -> String {
    let value = read_json(path, 4 * 1024 * 1024).unwrap_or_else(|_| json!({}));
    let date = value["installations"][format!("{scope}:{reference}")]
        .as_str()
        .unwrap_or("");
    if DateTime::parse_from_rfc3339(date).is_ok() {
        date.to_owned()
    } else {
        String::new()
    }
}
pub fn history_save(
    path: &Path,
    scope: &str,
    reference: &str,
    date: Option<&str>,
) -> io::Result<()> {
    if scope.is_empty() || !reference.starts_with("app/") || reference.split('/').count() != 4 {
        return Err(io::Error::other("Invalid installation identity"));
    }
    if date.is_some_and(|date| DateTime::parse_from_rfc3339(date).is_err()) {
        return Err(io::Error::other("Invalid installation date"));
    }
    let _lock = FileLock::acquire(&path.with_extension("json.lock"))?;
    let mut value = read_json(path, 4 * 1024 * 1024)
        .unwrap_or_else(|_| json!({"version":1,"installations":{}}));
    let dates = value["installations"]
        .as_object_mut()
        .ok_or_else(|| io::Error::other("Invalid installation history"))?;
    let key = format!("{scope}:{reference}");
    if let Some(date) = date {
        dates.insert(key, date.into());
    } else {
        dates.remove(&key);
    }
    write_json(path, &value)
}
pub fn config() -> glib::KeyFile {
    let file = glib::KeyFile::new();
    let _ = file.load_from_file(config_path(), glib::KeyFileFlags::KEEP_COMMENTS);
    file
}
pub fn update_config(edit: impl FnOnce(&glib::KeyFile)) -> io::Result<()> {
    let _lock = FileLock::acquire(&config_path().with_extension("conf.lock"))?;
    let file = config();
    edit(&file);
    atomic_write(&config_path(), file.to_data().as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cache_is_checksummed_and_expires_at_twelve_hours() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("catalog.json");
        let now = Utc::now();
        write_cache(&path, "source", &[json!({"id":"a.b.C","name":"C"})], now).unwrap();
        assert!(read_cache(&path, "source", now).is_some());
        assert!(read_cache(&path, "changed", now).is_none());
        assert!(fresh(
            now,
            now + chrono::Duration::seconds(CACHE_LIFETIME - 1)
        ));
        assert!(!fresh(now, now + chrono::Duration::seconds(CACHE_LIFETIME)));
        let mut damaged = read_json(&path, CACHE_LIMIT).unwrap();
        damaged["apps"][0]["name"] = "corrupt".into();
        write_json(&path, &damaged).unwrap();
        assert!(read_cache(&path, "source", now).is_none());
        fs::write(&path, b"{partial").unwrap();
        assert!(read_cache(&path, "source", now).is_none());
    }
    #[test]
    fn local_rebuild_preserves_refresh_age() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("catalog.json");
        let saved = Utc::now() - chrono::Duration::hours(11);
        write_cache(
            &path,
            "new-inputs",
            &[json!({"id":"a.b.C","name":"C"})],
            saved,
        )
        .unwrap();
        assert_eq!(
            read_cache(&path, "new-inputs", Utc::now())
                .unwrap()
                .saved_at,
            saved
        );
    }
    #[test]
    fn locking_is_nonblocking_and_recoverable() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("lock");
        let lock = FileLock::acquire(&path).unwrap();
        assert!(FileLock::acquire(&path).is_err());
        drop(lock);
        assert!(FileLock::acquire(&path).is_ok());
    }
    #[test]
    fn incomplete_temporary_file_does_not_replace_cache() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("cache.json");
        write_json(&path, &json!({"complete":true})).unwrap();
        fs::write(temp.path().join(".cache.json.crashed.tmp"), b"{broken").unwrap();
        assert_eq!(read_json(&path, 1024).unwrap(), json!({"complete":true}));
    }
}
