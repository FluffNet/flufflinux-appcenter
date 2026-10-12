//! UI-only translations. Catalog identities and transaction state stay unchanged.
mod selection;
use std::{collections::HashMap, ffi::{c_char, CStr, CString}, path::PathBuf, sync::OnceLock};

#[derive(Default)]
struct Translations {
    text: HashMap<String, String>,
    rtl: bool,
}
static TRANSLATIONS: OnceLock<Translations> = OnceLock::new();

fn directory() -> PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        if let Some(bin) = exe.parent().filter(|dir| dir.file_name().is_some_and(|name| name == "bin")) {
            if let Some(prefix) = bin.parent() {
                return prefix.join("share/flufflinux-appcenter/translations");
            }
        }
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("translations")
}

fn load(system_languages: Vec<String>) -> Translations {
    let mut result = Translations::default();
    let mut selected = false;
    for catalog in selection::application_catalogs(system_languages) {
        if catalog.name == "en" { break; }
        let Ok(data) = std::fs::read(directory().join(format!("{}.json", catalog.name))) else { continue; };
        let Ok(text) = serde_json::from_slice::<HashMap<String, String>>(&data) else { continue; };
        if !selected { result.rtl = catalog.right_to_left; selected = true; }
        for (source, translated) in text {
            if !translated.trim().is_empty() { result.text.entry(source).or_insert(translated); }
        }
    }
    result
}

pub fn translate(source: &str) -> String {
    TRANSLATIONS.get().and_then(|data| data.text.get(source)).cloned().unwrap_or_else(|| source.to_owned())
}

/// Presentation-only substitution. Never translate app identities or rescan
/// inserted names for placeholders. Isolates keep mixed-script values readable.
pub fn format(source: &str, arguments: &[&str]) -> String {
    substitute(&translate(source), arguments, TRANSLATIONS.get().is_some_and(|data| data.rtl))
}

fn substitute(template: &str, arguments: &[&str], rtl: bool) -> String {
    let mut result = String::new();
    let mut remaining = template;
    while let Some(start) = remaining.find('%') {
        result.push_str(&remaining[..start]);
        remaining = &remaining[start + 1..];
        let digits = remaining.bytes().take_while(u8::is_ascii_digit).count();
        let index = remaining[..digits].parse::<usize>().ok().and_then(|number| number.checked_sub(1));
        if let Some(argument) = index.and_then(|index| arguments.get(index)) {
            if rtl { result.push('\u{2068}'); }
            result.push_str(argument);
            if rtl { result.push('\u{2069}'); }
            remaining = &remaining[digits..];
        } else {
            result.push('%');
        }
    }
    result.push_str(remaining);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn placeholders(value: &str) -> BTreeMap<String, usize> {
        let mut counts = BTreeMap::new();
        for tail in value.split('%').skip(1) {
            let digits: String = tail.chars().take_while(char::is_ascii_digit).collect();
            if !digits.is_empty() { *counts.entry(digits).or_default() += 1; }
        }
        counts
    }

    #[test]
    fn arguments_are_not_translated_or_reinterpreted() {
        assert_eq!(substitute("Remove %1? %2", &["App %2", "stable"], false), "Remove App %2? stable");
        assert_eq!(substitute("%1 / %2", &["Firefox", "128 MiB"], true), "\u{2068}Firefox\u{2069} / \u{2068}128 MiB\u{2069}");
        assert_eq!(substitute("50% %0 %99 %", &[], false), "50% %0 %99 %");
    }

    #[test]
    fn authored_catalogs_preserve_placeholders_and_safe_text() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("translations");
        let english: HashMap<String, String> = serde_json::from_slice(&std::fs::read(root.join("en.json")).unwrap()).unwrap();
        for entry in std::fs::read_dir(root).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().is_none_or(|extension| extension != "json") { continue; }
            let entries: HashMap<String, String> = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
            let name = path.file_stem().unwrap().to_str().unwrap();
            // Regional files intentionally override only differing wording.
            if !["pt_BR", "de_CH"].contains(&name) {
                assert_eq!(entries.len(), english.len(), "{}: incomplete base catalog", path.display());
            }
            for (source, translated) in &entries {
                assert!(english.contains_key(source), "{}: obsolete key {source}", path.display());
                assert!(!translated.trim().is_empty(), "{}: empty {source}", path.display());
                assert_eq!(placeholders(source), placeholders(translated), "{}: placeholders for {source}", path.display());
                assert!(!translated.contains(['\u{2013}', '\u{2014}', '\0']), "{}: unsupported punctuation for {source}", path.display());
                if name == "pa_Arab" {
                    assert!(!translated.chars().any(|ch| ('\u{0a00}'..='\u{0a7f}').contains(&ch)), "{}: wrong Punjabi script for {source}", path.display());
                }
            }
        }
    }
}

#[no_mangle]
/// # Safety
/// `languages` is a live UTF-8 JSON array, terminated by NUL, for this call.
pub unsafe extern "C" fn fluff_i18n_initialize(languages: *const c_char) -> bool {
    let choices = if languages.is_null() { Vec::new() } else {
        serde_json::from_slice(unsafe { CStr::from_ptr(languages) }.to_bytes()).unwrap_or_default()
    };
    TRANSLATIONS.get_or_init(|| load(choices)).rtl
}

#[no_mangle]
/// # Safety
/// `context` and `source` are null or live NUL-terminated UTF-8 strings. Free the result with
/// `fluff_backend_string_free`. Missing translations return null to Qt.
pub unsafe extern "C" fn fluff_i18n_translate(context: *const c_char, source: *const c_char) -> *mut c_char {
    if source.is_null() { return std::ptr::null_mut(); }
    let source = unsafe { CStr::from_ptr(source) }.to_string_lossy();
    let context = if context.is_null() { Default::default() } else { unsafe { CStr::from_ptr(context) }.to_string_lossy() };
    TRANSLATIONS.get().and_then(|data| data.text.get(&format!("{context}\u{4}{source}")).or_else(|| data.text.get(source.as_ref())))
        .and_then(|value| CString::new(value.as_str()).ok())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}
