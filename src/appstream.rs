use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Clone, Default)]
pub struct App {
    pub id: String,
    pub name: String,
    pub summary: String,
    pub description: String,
    pub icon: String,
    pub category: String,
    pub developer: String,
    pub license: String,
    pub homepage: String,
    pub screenshots: Vec<String>,
}

pub fn load_catalog() -> Vec<App> {
    let mut apps = HashMap::<String, App>::new();
    let mut files = Vec::new();
    collect_files(Path::new("/var/lib/flatpak/appstream"), 0, &mut files);
    if let Some(home) = std::env::var_os("HOME") {
        collect_files(
            &PathBuf::from(home).join(".local/share/flatpak/appstream"),
            0,
            &mut files,
        );
    }
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
            if let Some(app) = parse_component(component, &path) {
                apps.entry(app.id.clone())
                    .and_modify(|current| merge(current, &app))
                    .or_insert(app);
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
    let categories: Vec<_> = blocks(xml, "category")
        .into_iter()
        .map(clean_markup)
        .collect();
    let category = display_category(&categories).to_string();
    let developer = base_text(xml, "developer_name")
        .or_else(|| base_text(xml, "developer-name"))
        .or_else(|| element(xml, "developer").and_then(|value| base_text(value, "name")))
        .unwrap_or_default();
    let license = base_text(xml, "project_license").unwrap_or_default();
    let homepage = tagged_text(xml, "url", "homepage").unwrap_or_default();
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
        developer,
        license,
        homepage,
        screenshots,
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
    fill!(developer);
    fill!(license);
    fill!(homepage);
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

fn escape_json(value: &str) -> String {
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
            "{{\"id\":{},\"name\":{},\"summary\":{},\"description\":{},\"icon\":{},\"category\":{},\"developer\":{},\"license\":{},\"homepage\":{},\"screenshots\":[{}],\"searchName\":{},\"searchSummary\":{},\"searchDescription\":{},\"searchMetadata\":{},\"searchHaystack\":{}}}",
            escape_json(&app.id), escape_json(&app.name), escape_json(&app.summary),
            escape_json(&app.description), escape_json(&app.icon), escape_json(&app.category),
            escape_json(&app.developer), escape_json(&app.license), escape_json(&app.homepage), screenshots,
            escape_json(&search_name), escape_json(&search_summary),
            escape_json(&search_description), escape_json(&search_metadata),
            escape_json(&search_haystack)
        ));
    }
    output.push(']');
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_a_desktop_component() {
        let xml = r#"<component type="desktop-application"><id>org.fluff.Test</id><name>Test &amp; App</name><summary>Small test</summary><categories><category>Utility</category></categories></component>"#;
        let app = parse_component(xml, Path::new("/tmp/appstream.xml")).unwrap();
        assert_eq!(app.name, "Test & App");
        assert_eq!(app.category, "Utilities");
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
