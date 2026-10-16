//! Download screenshots outside Qt's network-image decoder. Cancelling that
//! decoder mid-read can leak a texture in Qt 6.12. Qt only sees complete local
//! files here; workers are bounded and killed when their page goes away.
use super::{storage, text};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    time::{Duration, Instant, SystemTime},
};

pub const IMAGE_LIMIT: u64 = 8 * 1024 * 1024;
const CACHE_LIMIT: u64 = 128 * 1024 * 1024;
const LIFETIME: Duration = Duration::from_secs(storage::CACHE_LIFETIME as u64);

pub fn valid_url(value: &str) -> bool {
    value.len() <= 8192
        && url::Url::parse(value).is_ok_and(|u| {
            matches!(u.scheme(), "http" | "https")
                && u.host_str().is_some()
                && u.username().is_empty()
                && u.password().is_none()
        })
}
fn path(root: &Path, source: &str) -> PathBuf {
    root.join(format!("{:x}.image", Sha256::digest(source.as_bytes())))
}
fn cached(root: &Path, source: &str) -> Option<PathBuf> {
    let path = path(root, source);
    let metadata = fs::symlink_metadata(&path).ok()?;
    (metadata.file_type().is_file()
        && (1..=IMAGE_LIMIT).contains(&metadata.len())
        && metadata.modified().ok()?.elapsed().ok()? < LIFETIME)
        .then_some(path)
}
fn trim(root: &Path, incoming: u64) -> std::io::Result<()> {
    let mut entries = vec![];
    for entry in fs::read_dir(root)?.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !(name.ends_with(".image") || name.starts_with(".download-")) {
            continue;
        }
        let meta = fs::symlink_metadata(entry.path())?;
        if !meta.is_file() {
            continue;
        }
        let modified = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
        // A killed worker can leave an incomplete temporary file. Workers hold
        // the cache lock throughout writing, so none can still be in use here.
        if name.starts_with(".download-") || modified.elapsed().is_ok_and(|age| age >= LIFETIME) {
            fs::remove_file(entry.path())?;
        } else {
            entries.push((modified, meta.len(), entry.path()));
        }
    }
    entries.sort_by_key(|entry| entry.0);
    let mut total: u64 = entries.iter().map(|entry| entry.1).sum();
    let mut count = entries.len();
    for (_, size, path) in entries {
        if total + incoming <= CACHE_LIMIT && count < 128 {
            break;
        }
        fs::remove_file(path)?;
        total -= size;
        count -= 1;
    }
    Ok(())
}
fn download(source: &str) -> Result<Vec<u8>, String> {
    let agent = super::http::agent(Duration::from_secs(20));
    let mut current = url::Url::parse(source).map_err(|e| e.to_string())?;
    for _ in 0..5 {
        let mut response = agent
            .get(current.as_str())
            .call()
            .map_err(|e| e.to_string())?;
        if response.status().is_redirection() {
            let next = current
                .join(
                    response
                        .headers()
                        .get("Location")
                        .and_then(|h| h.to_str().ok())
                        .ok_or("Missing image redirect")?,
                )
                .map_err(|e| e.to_string())?;
            if !valid_url(next.as_str()) || current.scheme() == "https" && next.scheme() != "https"
            {
                return Err("Unsafe image redirect".into());
            }
            current = next;
            continue;
        }
        if response.status() != 200 {
            return Err("Image unavailable".into());
        }
        let mut data = vec![];
        response
            .body_mut()
            .as_reader()
            .take(IMAGE_LIMIT + 1)
            .read_to_end(&mut data)
            .map_err(|e| e.to_string())?;
        if data.is_empty() || data.len() as u64 > IMAGE_LIMIT {
            return Err("Image size limit exceeded".into());
        }
        return Ok(data);
    }
    Err("Too many image redirects".into())
}
fn fetch(root: &Path, source: &str) -> Result<PathBuf, String> {
    if !valid_url(source) {
        return Err("Invalid image URL".into());
    }
    if let Some(path) = cached(root, source) {
        return Ok(path);
    }
    let data = download(source)?;
    let waiting = Instant::now();
    let _lock = loop {
        match storage::FileLock::acquire(&root.join("cache.lock")) {
            Ok(lock) => break lock,
            Err(error)
                if error.kind() == std::io::ErrorKind::WouldBlock
                    && waiting.elapsed() < Duration::from_secs(1) =>
            {
                std::thread::sleep(Duration::from_millis(10))
            }
            Err(error) => return Err(error.to_string()),
        }
    };
    trim(root, data.len() as u64).map_err(|e| e.to_string())?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".download-")
        .tempfile_in(root)
        .map_err(|e| e.to_string())?;
    temporary.write_all(&data).map_err(|e| e.to_string())?;
    let path = path(root, source);
    temporary.persist(&path).map_err(|e| e.to_string())?;
    Ok(path)
}
pub fn worker(request: &Value) -> Value {
    match fetch(
        &storage::cache_dir().join("screenshots"),
        text(request, "url"),
    ) {
        Ok(path) => {
            json!({"state":"ready","source":url::Url::from_file_path(path).unwrap().as_str()})
        }
        Err(_) => json!({"state":"error","source":""}),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn serve(body: Vec<u8>, declared: usize) -> (String, std::thread::JoinHandle<()>) {
        let server = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let source = format!("http://{}/image.png", server.local_addr().unwrap());
        let task = std::thread::spawn(move || {
            let (mut connection, _) = server.accept().unwrap();
            connection
                .set_read_timeout(Some(Duration::from_secs(2)))
                .unwrap();
            let mut request = [0; 4096];
            connection.read(&mut request).unwrap();
            write!(
                connection,
                "HTTP/1.1 200 OK\r\nContent-Length: {declared}\r\nConnection: close\r\n\r\n"
            )
            .unwrap();
            let _ = connection.write_all(&body);
        });
        (source, task)
    }
    #[test]
    fn downloads_are_atomic_cached_and_incomplete_or_oversized_bodies_fail() {
        let root = tempfile::tempdir().unwrap();
        let (source, server) = serve(b"image bytes".to_vec(), 11);
        let saved = fetch(root.path(), &source).unwrap();
        server.join().unwrap();
        assert_eq!(fs::read(&saved).unwrap(), b"image bytes");
        // No listener remains: the second request must read the disk cache.
        assert_eq!(fetch(root.path(), &source).unwrap(), saved);
        for (data, length) in [
            (vec![0; IMAGE_LIMIT as usize + 1], IMAGE_LIMIT as usize + 1),
            (b"partial".to_vec(), 100),
        ] {
            let (url, server) = serve(data, length);
            assert!(fetch(root.path(), &url).is_err());
            server.join().unwrap();
            assert!(!path(root.path(), &url).exists());
        }
        assert_eq!(fs::read(&saved).unwrap(), b"image bytes");
        fs::File::open(&saved)
            .unwrap()
            .set_modified(SystemTime::now() - LIFETIME - Duration::from_secs(1))
            .unwrap();
        assert!(cached(root.path(), &source).is_none());
    }
    #[test]
    fn disk_budget_is_enforced_by_bytes_as_well_as_count() {
        let root = tempfile::tempdir().unwrap();
        for n in 0..16 {
            fs::File::create(root.path().join(format!("{n}.image")))
                .unwrap()
                .set_len(IMAGE_LIMIT)
                .unwrap();
        }
        trim(root.path(), IMAGE_LIMIT).unwrap();
        let bytes: u64 = fs::read_dir(root.path())
            .unwrap()
            .flatten()
            .map(|e| e.metadata().unwrap().len())
            .sum();
        assert!(bytes + IMAGE_LIMIT <= CACHE_LIMIT);
    }
    #[test]
    fn only_http_images_and_bounded_cache_are_accepted() {
        assert!(valid_url("https://example.org/image.png"));
        for bad in [
            "file:///etc/passwd",
            "https://user:secret@example.org/a",
            "data:image/png,abc",
        ] {
            assert!(!valid_url(bad));
        }
        let root = tempfile::tempdir().unwrap();
        for n in 0..130 {
            fs::write(root.path().join(format!("{n}.image")), b"image").unwrap();
        }
        fs::write(root.path().join(".download-interrupted"), b"partial").unwrap();
        trim(root.path(), 1024).unwrap();
        assert_eq!(fs::read_dir(root.path()).unwrap().count(), 127);
        assert!(!root.path().join(".download-interrupted").exists());
        let source = "https://example.org/cached.png";
        fs::write(path(root.path(), source), b"cached").unwrap();
        assert!(cached(root.path(), source).is_some());
        assert_eq!(
            fetch(root.path(), source).unwrap(),
            path(root.path(), source)
        );
    }
}
