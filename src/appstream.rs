use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::ffi::{CStr, CString, c_char, c_void};

unsafe extern "C" {
    fn fluff_visit_catalogs(visit: unsafe extern "C" fn(*const c_char, *const c_char, *const c_char, *mut c_void), data: *mut c_void);
    fn fluff_catalog_download_size(remote: *const c_char, url: *const c_char, flatpak_ref: *const c_char) -> f64;
    fn fluff_catalog_app_installed(id: *const c_char) -> bool;
}
unsafe extern "C" fn catalog_root(path: *const c_char, remote: *const c_char, url: *const c_char, data: *mut c_void) {
    if path.is_null() { return; }
    let roots = unsafe { &mut *(data as *mut Vec<(PathBuf, String, String)>) };
    roots.push((PathBuf::from(unsafe { CStr::from_ptr(path) }.to_string_lossy().into_owned()),
        unsafe { CStr::from_ptr(remote) }.to_string_lossy().into_owned(),
        unsafe { CStr::from_ptr(url) }.to_string_lossy().into_owned()));
}

#[derive(Clone, Default)]
pub struct App {
    pub id: String,
    pub name: String,
    pub summary: String,
    pub description: String,
    pub icon: String,
    pub category: String,
    pub categories: Vec<String>,
    pub mime_types: Vec<String>,
    pub developer: String,
    pub license: String,
    pub homepage: String,
    pub version: String,
    pub release_date: String,
    pub release_timestamp: Option<u64>,
    pub download_bytes: Option<u64>,
    pub screenshots: Vec<String>,
    pub flatpak_ref: String,
    pub remote: String,
    pub source_url: String,
    pub sources: Vec<App>,
}

pub fn load_catalog() -> Vec<App> {
    let mut apps = HashMap::<String, App>::new();
    let exclusions = crate::catalog_exclusions::load();
    let mut roots = Vec::<(PathBuf, String, String)>::new();
    unsafe { fluff_visit_catalogs(catalog_root, &mut roots as *mut _ as *mut c_void); }
    for (root, remote, url) in roots {
      let mut files = Vec::new();
      collect_files(&root, 0, &mut files);
      files.sort();
      for path in files {
        let Some(text) = read_metadata(&path) else {
            continue;
        };
        for component in blocks(&text, "component") {
            if !component.contains("type=\"desktop")
                && !component.contains("type='desktop")
                && !component.contains("<launchable")
            {
                continue;
            }
            if let Some(mut app) = parse_component(component, &path) {
                if exclusions.should_hide(&app.id, &app.flatpak_ref, |id| CString::new(id).ok()
                    .is_some_and(|id| unsafe { fluff_catalog_app_installed(id.as_ptr()) })) { continue; }
                app.remote = remote.clone();
                app.source_url = url.clone();
                if let (Ok(remote), Ok(url), Ok(reference)) = (CString::new(remote.as_str()),
                        CString::new(url.as_str()), CString::new(app.flatpak_ref.as_str())) {
                    let size = unsafe { fluff_catalog_download_size(remote.as_ptr(), url.as_ptr(), reference.as_ptr()) };
                    if size >= 0.0 { app.download_bytes = Some(size as u64); }
                }
                let variant = app.clone();
                app.sources.push(variant);
                let key = app.id.strip_suffix(".desktop").unwrap_or(&app.id).to_string();
                apps.entry(key)
                    .and_modify(|current| merge(current, &app))
                    .or_insert(app);
            }
        }
      }
    }
    let mut result: Vec<_> = apps.into_values().collect();
    result.sort_by_key(|app| app.name.to_lowercase());
    result
}

fn collect_files(directory: &Path, depth: u8, files: &mut Vec<PathBuf>) {
    if depth > 5 {
        return;
    }
    // Flatpak replaces/prunes deployment-hash directories during refreshes.
    // Read only the active snapshot and retain the symlink in icon paths so
    // an already-open catalog can still load artwork after a later refresh.
    let active = directory.join("active");
    if active.join("appstream.xml.gz").is_file() || active.join("appstream.xml").is_file() {
        collect_files(&active, depth + 1, files);
        return;
    }
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_files(&path, depth + 1, files);
        } else if matches!(
            path.extension().and_then(|value| value.to_str()),
            Some("xml" | "gz")
        ) {
            files.push(path);
        }
    }
}

fn read_metadata(path: &Path) -> Option<String> {
    if path.extension().and_then(|value| value.to_str()) == Some("gz") {
        let output = Command::new("gzip").arg("-dc").arg(path).output().ok()?;
        output
            .status
            .success()
            .then(|| String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        fs::read_to_string(path).ok()
    }
}

fn parse_component(xml: &str, catalog_path: &Path) -> Option<App> {
    let id = base_text(xml, "id")?;
    let name = base_text(xml, "name").filter(|value| !value.is_empty())?;
    let summary = base_text(xml, "summary").unwrap_or_default();
    let description = base_description(xml);
    let icon = preferred_icon(xml, catalog_path);
    let flatpak_ref = tagged_text(xml, "bundle", "flatpak").unwrap_or_default();
    let remote = catalog_path
        .components()
        .map(|part| part.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .windows(2)
        .find(|pair| pair[0] == "appstream")
        .map(|pair| pair[1].clone())
        .unwrap_or_default();
    let categories: Vec<_> = blocks(xml, "category")
        .into_iter()
        .map(clean_markup)
        .collect();
    let category = display_category(&categories).to_string();
    let mut seen_mime = HashSet::new();
    let mime_types = blocks(xml, "mediatype").into_iter().chain(blocks(xml, "mimetype"))
        .map(|value| clean_markup(value).to_ascii_lowercase())
        .filter(|value| value.contains('/') && seen_mime.insert(value.clone())).collect();
    let developer = base_text(xml, "developer_name")
        .or_else(|| base_text(xml, "developer-name"))
        .or_else(|| element(xml, "developer").and_then(|value| base_text(value, "name")))
        .unwrap_or_default();
    let license = base_text(xml, "project_license").unwrap_or_default();
    let homepage = tagged_text(xml, "url", "homepage").unwrap_or_default();
    let version = release_version(xml);
    let release = first_release(xml).unwrap_or_default();
    let release_date = attribute(release, "date").unwrap_or_default();
    let release_timestamp = attribute(release, "timestamp").and_then(|value| value.parse::<u64>().ok()).filter(|value| *value > 0);
    let mut seen_screenshots = HashSet::new();
    let screenshots = blocks(xml, "screenshot")
        .into_iter()
        .filter_map(preferred_screenshot)
        .filter(|value| value.starts_with("http://") || value.starts_with("https://"))
        .filter(|value| seen_screenshots.insert(value.clone()))
        .take(8)
        .collect();
    Some(App {
        id,
        name,
        summary,
        description,
        icon,
        category,
        categories,
        mime_types,
        developer,
        license,
        homepage,
        version,
        release_date,
        release_timestamp,
        download_bytes: None,
        screenshots,
        flatpak_ref,
        remote,
        source_url: String::new(),
        sources: Vec::new(),
    })
}

fn preferred_screenshot(screenshot: &str) -> Option<String> {
    let images = blocks(screenshot, "image");
    images
        .iter()
        .find(|image| image.contains("type=\"source\"") || image.contains("type='source'"))
        .or_else(|| {
            images.iter().find(|image| {
                !image.contains("type=\"thumbnail\"") && !image.contains("type='thumbnail'")
            })
        })
        .or_else(|| images.first())
        .map(|image| clean_markup(image))
}

fn merge(current: &mut App, incoming: &App) {
    for source in &incoming.sources {
        if !current.sources.iter().any(|existing| existing.remote == source.remote
            && existing.source_url == source.source_url && existing.flatpak_ref == source.flatpak_ref) {
            current.sources.push(source.clone());
        }
    }
    macro_rules! fill {
        ($field:ident) => {
            if current.$field.is_empty() {
                current.$field = incoming.$field.clone();
            }
        };
    }
    fill!(summary);
    fill!(description);
    fill!(icon);
    fill!(category);
    fill!(categories);
    fill!(mime_types);
    fill!(developer);
    fill!(license);
    fill!(homepage);
    fill!(version);
    fill!(flatpak_ref);
    fill!(remote);
    if current.screenshots.is_empty() {
        current.screenshots = incoming.screenshots.clone();
    }
}

fn display_category(values: &[String]) -> &'static str {
    let joined = values.join(" ").to_lowercase();
    for (needle, display) in [
        ("game", "Games"),
        ("development", "Development"),
        ("graphics", "Graphics"),
        ("audio", "Audio & Video"),
        ("video", "Audio & Video"),
        ("network", "Internet"),
        ("office", "Office"),
        ("education", "Education"),
        ("science", "Science"),
        ("utility", "Utilities"),
        ("system", "System"),
    ] {
        if joined.contains(needle) {
            return display;
        }
    }
    "Other"
}

fn preferred_icon(xml: &str, catalog_path: &Path) -> String {
    if let Some(value) = tagged_text(xml, "icon", "cached") {
        if let Some(catalog_dir) = catalog_path.parent() {
            for size in ["128x128", "64x64"] {
                let candidate = catalog_dir.join("icons").join(size).join(&value);
                if candidate.is_file() {
                    return candidate.to_string_lossy().into_owned();
                }
            }
        }
        return value;
    }
    for kind in ["local", "stock", "remote"] {
        if let Some(value) = tagged_text(xml, "icon", kind) {
            return value;
        }
    }
    base_text(xml, "icon").unwrap_or_else(|| "application-x-executable".into())
}

fn attribute(tag: &str, name: &str) -> Option<String> {
    let mut rest = &tag[tag.find(char::is_whitespace)?..];
    loop {
        rest = rest.trim_start();
        let equals = rest.find('=')?;
        let key = rest[..equals].trim();
        rest = rest[equals + 1..].trim_start();
        let quote = rest.chars().next()?;
        if quote != '\'' && quote != '"' {
            return None;
        }
        rest = &rest[1..];
        let end = rest.find(quote)?;
        if key == name {
            return Some(clean_markup(&rest[..end]));
        }
        rest = &rest[end + 1..];
    }
}

fn release_version(xml: &str) -> String {
    let Some(releases) = element(xml, "releases") else {
        return String::new();
    };
    // Collection metadata publishes the current release first. Read opening
    // tags as releases may be self-closing when no release notes are present.
    releases
        .match_indices("<release")
        .filter(|(offset, _)| {
            releases
                .as_bytes()
                .get(offset + 8)
                .is_some_and(u8::is_ascii_whitespace)
        })
        .find_map(|(offset, _)| {
            let rest = &releases[offset..];
            attribute(&rest[..=rest.find('>')?], "version").filter(|value| !value.is_empty())
        })
        .unwrap_or_default()
}

fn first_release(xml: &str) -> Option<&str> {
    let releases = element(xml, "releases")?;
    releases.match_indices("<release").filter(|(offset, _)| {
        releases.as_bytes().get(offset + 8).is_some_and(u8::is_ascii_whitespace)
    }).find_map(|(offset, _)| {
        let rest = &releases[offset..];
        Some(&rest[..=rest.find('>')?])
    })
}

fn blocks<'a>(input: &'a str, tag: &str) -> Vec<&'a str> {
    let mut result = Vec::new();
    let mut rest = input;
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    while let Some(start) = rest.find(&open) {
        let candidate = &rest[start..];
        let boundary = candidate.as_bytes().get(open.len()).copied();
        if !matches!(
            boundary,
            Some(b'>') | Some(b' ') | Some(b'\t') | Some(b'\r') | Some(b'\n')
        ) {
            rest = &candidate[open.len()..];
            continue;
        }
        let Some(end) = candidate.find(&close) else {
            break;
        };
        let end = end + close.len();
        result.push(&candidate[..end]);
        rest = &candidate[end..];
    }
    result
}

fn element<'a>(input: &'a str, tag: &str) -> Option<&'a str> {
    blocks(input, tag).into_iter().next()
}
fn base_text(input: &str, tag: &str) -> Option<String> {
    blocks(input, tag)
        .into_iter()
        .find(|block| !is_localized(block))
        .map(clean_markup)
}

fn base_description(input: &str) -> String {
    let Some(description) = blocks(input, "description")
        .into_iter()
        .find(|block| !is_localized(block))
    else {
        return String::new();
    };
    let mut paragraphs: Vec<String> = blocks(description, "p")
        .into_iter()
        .filter(|block| !is_localized(block))
        .map(clean_markup)
        .filter(|text| !text.is_empty())
        .collect();
    paragraphs.extend(
        blocks(description, "li")
            .into_iter()
            .filter(|block| !is_localized(block))
            .map(clean_markup)
            .filter(|text| !text.is_empty()),
    );
    paragraphs.join("\n\n")
}

fn is_localized(block: &str) -> bool {
    block
        .split_once('>')
        .map(|(opening_tag, _)| opening_tag.contains("xml:lang=") || opening_tag.contains(" lang="))
        .unwrap_or(false)
}
fn tagged_text(input: &str, tag: &str, kind: &str) -> Option<String> {
    blocks(input, tag)
        .into_iter()
        .find(|block| {
            block.contains(&format!("type=\"{kind}\"")) || block.contains(&format!("type='{kind}'"))
        })
        .map(clean_markup)
}

fn clean_markup(value: &str) -> String {
    let mut plain = String::with_capacity(value.len());
    let mut in_tag = false;
    for character in value.chars() {
        match character {
            '<' => {
                in_tag = true;
                plain.push(' ');
            }
            '>' => in_tag = false,
            _ if !in_tag => plain.push(character),
            _ => {}
        }
    }
    let decoded = plain
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'");
    decoded.split_whitespace().collect::<Vec<_>>().join(" ")
}

pub(crate) fn escape_json(value: &str) -> String {
    let mut result = String::with_capacity(value.len() + 2);
    result.push('"');
    for c in value.chars() {
        match c {
            '"' => result.push_str("\\\""),
            '\\' => result.push_str("\\\\"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            c if c.is_control() => result.push_str(&format!("\\u{:04x}", c as u32)),
            c => result.push(c),
        }
    }
    result.push('"');
    result
}

pub fn to_json(apps: &[App]) -> String {
    let mut output = String::from("[");
    for (index, app) in apps.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        let screenshots = app
            .screenshots
            .iter()
            .map(|value| escape_json(value))
            .collect::<Vec<_>>()
            .join(",");
        let search_name = app.name.to_lowercase();
        let search_summary = app.summary.to_lowercase();
        let search_description = app.description.to_lowercase();
        let search_metadata =
            format!("{} {} {}", app.developer, app.id, app.category).to_lowercase();
        let search_haystack =
            format!("{search_name} {search_summary} {search_description} {search_metadata}");
        output.push_str(&format!(
            "{{\"id\":{},\"name\":{},\"summary\":{},\"description\":{},\"icon\":{},\"category\":{},\"developer\":{},\"license\":{},\"homepage\":{},\"screenshots\":[{}],\"searchName\":{},\"searchSummary\":{},\"searchDescription\":{},\"searchMetadata\":{},\"searchHaystack\":{},\"flatpakRef\":{},\"remote\":{},\"version\":{},\"sourceUrl\":{},\"sources\":{},\"releaseDate\":{},\"releaseTimestamp\":{},\"downloadBytes\":{}}}",
            escape_json(&app.id), escape_json(&app.name), escape_json(&app.summary),
            escape_json(&app.description), escape_json(&app.icon), escape_json(&app.category),
            escape_json(&app.developer), escape_json(&app.license), escape_json(&app.homepage), screenshots,
            escape_json(&search_name), escape_json(&search_summary),
            escape_json(&search_description), escape_json(&search_metadata),
            escape_json(&search_haystack), escape_json(&app.flatpak_ref), escape_json(&app.remote),
            escape_json(&app.version), escape_json(&app.source_url), to_json(&app.sources),
            escape_json(&app.release_date), app.release_timestamp.map(|value| value.to_string()).unwrap_or("null".into()),
            app.download_bytes.map(|value| value.to_string()).unwrap_or("null".into())
        ));
        output.pop();
        output.push_str(&format!(",\"categories\":[{}],\"mimeTypes\":[{}]}}",
            app.categories.iter().map(|v| escape_json(v)).collect::<Vec<_>>().join(","),
            app.mime_types.iter().map(|v| escape_json(v)).collect::<Vec<_>>().join(",")));
    }
    output.push(']');
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn serializes_release_dates_and_unknown_sizes_without_inventing_values() {
        let prefix = "<component type='desktop-application'><id>org.example.Date</id><name>Date</name>";
        let app = parse_component(&format!("{prefix}<releases><release version='2' timestamp='1789940480' date='2026-09-21'/><release version='1' date='2020-01-01'/></releases></component>"), Path::new("/tmp/appstream.xml")).unwrap();
        assert_eq!(app.release_timestamp, Some(1789940480));
        assert_eq!(app.release_date, "2026-09-21");
        assert_eq!(app.download_bytes, None);
        assert!(to_json(&[app.clone()]).contains("\"downloadBytes\":null"));
        let zero = App { download_bytes: Some(0), ..app };
        assert!(to_json(&[zero]).contains("\"downloadBytes\":0"));
        let missing = parse_component(&format!("{prefix}<releases><release version='1' timestamp='bad'/></releases></component>"), Path::new("/tmp/appstream.xml")).unwrap();
        assert_eq!(missing.release_timestamp, None);
        assert!(missing.release_date.is_empty());
    }
    #[test]
    fn keeps_distinct_sources_without_duplicate_catalog_cards() {
        let base = App { id: "org.example.App".into(), name: "Test".into(), remote: "stable".into(),
            flatpak_ref: "app/org.example.App/x86_64/stable".into(), version: "1.0".into(),
            source_url: "https://example.org/stable".into(), ..App::default() };
        let mut current = base.clone();
        current.sources.push(base.clone());
        let mut beta = App { remote: "beta".into(), flatpak_ref: "app/org.example.App/x86_64/beta".into(),
            source_url: "https://example.org/beta".into(), version: "2.0".into(), ..base.clone() };
        beta.sources.push(beta.clone());
        merge(&mut current, &beta);
        merge(&mut current, &beta); // System/user copies of the same origin collapse.
        assert_eq!(current.sources.len(), 2);
        assert_eq!(current.version, "1.0");
        assert_eq!(current.sources[1].version, "2.0");
        assert!(current.sources.iter().all(|source| source.sources.is_empty()));
        assert!(to_json(&[current]).contains("\"sourceUrl\":\"https://example.org/beta\""));
    }
    #[test]
    fn reads_published_version_and_handles_missing_or_self_closing_releases() {
        let prefix = "<component type='desktop-application'><id>org.example.Version</id><name>Version</name>";
        for (releases, expected) in [
            ("<releases><release timestamp='200' type='stable' version='0.28.0'><description>Latest</description></release><release version='0.27.1'/></releases>", "0.28.0"),
            ("<releases><release type='development' version = \"2.0-beta1\" /></releases>", "2.0-beta1"),
            ("<releases><release x-version='wrong' version='1.0&amp;patch'/></releases>", "1.0&patch"),
            ("<releases><release timestamp='200'/></releases>", ""),
            ("", ""),
        ] {
            let app = parse_component(&format!("{prefix}{releases}</component>"), Path::new("/tmp/appstream.xml")).unwrap();
            assert_eq!(app.version, expected);
            assert!(to_json(&[app]).contains(&format!("\"version\":{}", escape_json(expected))));
        }
    }

    #[test]
    fn active_catalog_icons_survive_deployment_replacement() {
        use std::os::unix::fs::symlink;
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root =
            std::env::temp_dir().join(format!("fluff-appstream-{}-{unique}", std::process::id()));
        fs::create_dir(&root).unwrap();
        struct Cleanup(PathBuf);
        impl Drop for Cleanup {
            fn drop(&mut self) {
                let _ = fs::remove_dir_all(&self.0);
            }
        }
        let _cleanup = Cleanup(root.clone());
        let xml = "<component type='desktop-application'><id>org.example.Icon</id><name>Icon</name><icon type='cached'>org.example.Icon.png</icon><releases><release version='1.0'/></releases></component>";
        for deployment in ["old", "new"] {
            fs::create_dir_all(root.join(deployment).join("icons/128x128")).unwrap();
            fs::write(root.join(deployment).join("appstream.xml"), xml).unwrap();
            fs::write(
                root.join(deployment)
                    .join("icons/128x128/org.example.Icon.png"),
                deployment,
            )
            .unwrap();
        }
        symlink("old", root.join("active")).unwrap();
        let mut files = Vec::new();
        collect_files(&root, 0, &mut files);
        assert_eq!(files, vec![root.join("active/appstream.xml")]);
        let app = parse_component(xml, &files[0]).unwrap();
        assert_eq!(
            Path::new(&app.icon),
            root.join("active/icons/128x128/org.example.Icon.png")
        );
        assert_eq!(fs::read_to_string(&app.icon).unwrap(), "old");
        fs::remove_file(root.join("active")).unwrap();
        symlink("new", root.join("active")).unwrap();
        fs::remove_dir_all(root.join("old")).unwrap();
        // Reuse the original in-memory app, just as opening details later does.
        assert_eq!(fs::read_to_string(&app.icon).unwrap(), "new");
    }
    #[test]
    fn parses_a_desktop_component() {
        let xml = r#"<component type="desktop-application"><id>org.fluff.Test</id><name>Test &amp; App</name><summary>Small test</summary><categories><category>Utility</category></categories></component>"#;
        let app = parse_component(xml, Path::new("/tmp/appstream.xml")).unwrap();
        assert_eq!(app.name, "Test & App");
        assert_eq!(app.category, "Utilities");
    }

    #[test]
    fn retains_raw_categories_and_declared_mime_types() {
        let xml = r#"<component type="desktop-application"><id>org.example.Viewer</id><name>PDF</name><categories><category>Office</category><category>Viewer</category></categories><provides><mediatype>application/pdf</mediatype><mediatype>image/png</mediatype></provides><mimetypes><mimetype>APPLICATION/PDF</mimetype><mimetype>image/jpeg</mimetype></mimetypes></component>"#;
        let app = parse_component(xml, Path::new("/tmp/appstream.xml")).unwrap();
        assert_eq!(app.categories, ["Office", "Viewer"]);
        assert_eq!(app.mime_types, ["application/pdf", "image/png", "image/jpeg"]);
        let json = to_json(&[app.clone()]);
        assert!(json.contains("\"categories\":[\"Office\",\"Viewer\"]"));
        assert!(json.contains("\"mimeTypes\":[\"application/pdf\",\"image/png\",\"image/jpeg\"]"));
        let mut missing = App { id: app.id.clone(), name: "PDF editor".into(), ..App::default() };
        assert!(missing.mime_types.is_empty(), "Never infer MIME support from an app's name");
        merge(&mut missing, &app);
        assert_eq!(missing.categories, app.categories);
        assert_eq!(missing.mime_types, app.mime_types);
    }

    #[test]
    fn keeps_flatpak_source_and_branch_for_installation() {
        let xml = r#"<component type="desktop-application"><id>org.example.Test.desktop</id><name>Test</name><bundle type="flatpak">app/org.example.Test/x86_64/beta</bundle></component>"#;
        let app = parse_component(
            xml,
            Path::new("/var/lib/flatpak/appstream/testing/x86_64/active/appstream.xml"),
        )
        .unwrap();
        assert_eq!(app.remote, "testing");
        assert_eq!(app.flatpak_ref, "app/org.example.Test/x86_64/beta");
        assert!(to_json(&[app]).contains("\"remote\":\"testing\""));
    }
    #[test]
    fn prefers_base_language_metadata() {
        let xml = r#"<component type="desktop-application"><id>org.fluff.Test</id><name xml:lang="sv">Test på svenska</name><name>English Test</name><summary xml:lang="he">בדיקה</summary><summary>Base summary</summary><description><p>Base description</p><p xml:lang="fr">Description française</p></description><launchable type="desktop-id">org.fluff.Test.desktop</launchable></component>"#;
        let app = parse_component(xml, Path::new("/tmp/appstream.xml")).unwrap();
        assert_eq!(app.name, "English Test");
        assert_eq!(app.summary, "Base summary");
        assert_eq!(app.description, "Base description");
    }
    #[test]
    fn serializes_escaped_strings() {
        let app = App {
            id: "a\"b".into(),
            name: "Line\nName".into(),
            ..App::default()
        };
        let json = to_json(&[app]);
        assert!(json.contains("a\\\"b"));
        assert!(json.contains("Line\\nName"));
        assert!(json.contains("\"searchName\":\"line\\nname\""));
    }

    #[test]
    fn keeps_one_source_image_per_unique_screenshot() {
        let xml = r#"
            <component type="desktop-application">
                <id>org.fluff.Test</id>
                <name>Screenshot Test</name>
                <screenshots>
                    <screenshot type="default">
                        <image type="thumbnail">https://example.test/first-thumb.png</image>
                        <image type="source">https://example.test/first.png</image>
                    </screenshot>
                    <screenshot>
                        <image type="source">https://example.test/second.png</image>
                    </screenshot>
                    <screenshot>
                        <image type="source">https://example.test/first.png</image>
                    </screenshot>
                </screenshots>
            </component>
        "#;
        let app = parse_component(xml, Path::new("/tmp/appstream.xml")).unwrap();
        assert_eq!(
            app.screenshots,
            vec![
                "https://example.test/first.png",
                "https://example.test/second.png"
            ]
        );
    }
}
