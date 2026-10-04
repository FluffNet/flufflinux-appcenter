//! One configuration file, with validated settings and atomic, locked updates.
use super::{flag, number, storage, text};
use serde_json::{json, Value};
use std::path::Path;
const SORTS: [&str; 6] = [
    "name-asc",
    "name-desc",
    "popularity-desc",
    "popularity-asc",
    "release-desc",
    "release-asc",
];
fn read(path: &Path) -> glib::KeyFile {
    let file = glib::KeyFile::new();
    if path
        .metadata()
        .is_ok_and(|m| m.is_file() && m.len() <= 1024 * 1024)
    {
        let _ = file.load_from_file(path, glib::KeyFileFlags::KEEP_COMMENTS);
    }
    file
}
fn edit(path: &Path, edit: impl FnOnce(&glib::KeyFile)) -> Result<(), String> {
    if path.as_os_str().is_empty() {
        return Ok(());
    }
    let _lock =
        storage::FileLock::acquire(&path.with_extension("conf.lock")).map_err(|e| e.to_string())?;
    let file = read(path);
    edit(&file);
    storage::atomic_write(path, file.to_data().as_bytes()).map_err(|e| e.to_string())
}
pub fn call(request: &Value) -> Value {
    let path = Path::new(text(request, "path"));
    match text(request, "operation") {
        "sort-read" => {
            let saved = read(path).string("Catalog", "homeSort").unwrap_or_default();
            json!({"value":if SORTS.contains(&saved.as_str()){saved.as_str()}else{"popularity-desc"}})
        }
        "sort-save" => {
            let value = text(request, "value");
            if !SORTS.contains(&value) {
                return json!({"valid":false});
            }
            let result = edit(path, |file| file.set_string("Catalog", "homeSort", value));
            json!({"valid":true,"value":value,"saved":result.is_ok(),"error":result.err()})
        }
        "window-read" => {
            let file = read(path);
            let width = file
                .integer("Window", "width")
                .ok()
                .filter(|&n| n >= 720)
                .unwrap_or(1180);
            let height = file
                .integer("Window", "height")
                .ok()
                .filter(|&n| n >= 520)
                .unwrap_or(760);
            let available_width = number(request, "width").max(1).min(i32::MAX as u64) as i32;
            let available_height = number(request, "height").max(1).min(i32::MAX as u64) as i32;
            let maximized = file
                .string("Window", "maximized")
                .map_or(true, |value| !value.eq_ignore_ascii_case("false"))
                || width > available_width
                || height > available_height;
            json!({"normalWidth":width,"normalHeight":height,"width":width.min(available_width),"height":height.min(available_height),"maximized":maximized})
        }
        "window-save" => {
            let width = number(request, "width");
            let height = number(request, "height");
            if width == 0 || height == 0 || width > i32::MAX as u64 || height > i32::MAX as u64 {
                return json!({"saved":false});
            }
            let result = edit(path, |file| {
                file.set_integer("Window", "width", width as i32);
                file.set_integer("Window", "height", height as i32);
                file.set_boolean("Window", "maximized", flag(request, "maximized"));
            });
            json!({"saved":result.is_ok(),"error":result.err()})
        }
        _ => json!({}),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn saves_preserve_unrelated_settings() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("settings.conf");
        std::fs::write(&path, "[Sources]\nremovedSystemSources=abc\n").unwrap();
        assert_eq!(
            call(&json!({"operation":"sort-save","path":path,"value":"name-asc"}))["saved"],
            true
        );
        assert_eq!(
            call(
                &json!({"operation":"window-save","path":path,"width":900,"height":600,"maximized":false})
            )["saved"],
            true
        );
        assert_eq!(
            read(&path)
                .string("Sources", "removedSystemSources")
                .unwrap(),
            "abc"
        );
        assert_eq!(
            call(&json!({"operation":"sort-read","path":path}))["value"],
            "name-asc"
        );
        assert_eq!(
            call(&json!({"operation":"window-read","path":path,"width":1920,"height":1080}))
                ["maximized"],
            false
        );
        assert_eq!(
            call(&json!({"operation":"window-read","path":path,"width":640,"height":480}))
                ["maximized"],
            true
        );
    }
    #[test]
    fn fresh_configuration_is_maximized_and_bad_sort_is_ignored() {
        assert_eq!(
            call(&json!({"operation":"window-read","path":"","width":1920,"height":1080}))
                ["maximized"],
            true
        );
        assert_eq!(
            call(&json!({"operation":"sort-save","path":"","value":"bad"}))["valid"],
            false
        );
    }
}
