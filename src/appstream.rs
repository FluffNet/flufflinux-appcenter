use std::collections::HashMap;
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

const CATALOG_DIRS: &[&str] = &[
    "/usr/share/swcatalog/xml",
    "/var/cache/swcatalog/xml",
    "/usr/share/app-info/xmls",
    "/var/lib/flatpak/appstream",
];
const METAINFO_DIRS: &[&str] = &["/usr/share/metainfo", "/usr/share/appdata"];

pub fn load_catalog() -> Vec<App> {
    let mut apps = HashMap::<String, App>::new();
    let mut files = Vec::new();
    for directory in CATALOG_DIRS.iter().chain(METAINFO_DIRS) {
        collect_files(Path::new(directory), 0, &mut files);
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
            if let Some(app) = parse_component(component) {
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

fn parse_component(xml: &str) -> Option<App> {
    let id = text(xml, "id")?;
    let name = text(xml, "name").filter(|value| !value.is_empty())?;
    let summary = text(xml, "summary").unwrap_or_default();
    let description = element(xml, "description")
        .map(clean_markup)
        .unwrap_or_default();
    let icon = preferred_icon(xml);
    let categories: Vec<_> = blocks(xml, "category")
        .into_iter()
        .map(clean_markup)
        .collect();
    let category = display_category(&categories).to_string();
    let developer = text(xml, "developer_name")
        .or_else(|| text(xml, "developer-name"))
        .unwrap_or_default();
    let license = text(xml, "project_license").unwrap_or_default();
    let homepage = tagged_text(xml, "url", "homepage").unwrap_or_default();
    let screenshots = blocks(xml, "image")
        .into_iter()
        .map(clean_markup)
        .filter(|value| value.starts_with("http://") || value.starts_with("https://"))
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

fn preferred_icon(xml: &str) -> String {
    for kind in ["cached", "local", "stock", "remote"] {
        if let Some(value) = tagged_text(xml, "icon", kind) {
            return value;
        }
    }
    text(xml, "icon").unwrap_or_else(|| "application-x-executable".into())
}

fn blocks<'a>(input: &'a str, tag: &str) -> Vec<&'a str> {
    let mut result = Vec::new();
    let mut rest = input;
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    while let Some(start) = rest.find(&open) {
        let candidate = &rest[start..];
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
fn text(input: &str, tag: &str) -> Option<String> {
    element(input, tag).map(clean_markup)
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
        output.push_str(&format!(
            "{{\"id\":{},\"name\":{},\"summary\":{},\"description\":{},\"icon\":{},\"category\":{},\"developer\":{},\"license\":{},\"homepage\":{},\"screenshots\":[{}]}}",
            escape_json(&app.id), escape_json(&app.name), escape_json(&app.summary),
            escape_json(&app.description), escape_json(&app.icon), escape_json(&app.category),
            escape_json(&app.developer), escape_json(&app.license), escape_json(&app.homepage), screenshots
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
        let app = parse_component(xml).unwrap();
        assert_eq!(app.name, "Test & App");
        assert_eq!(app.category, "Utilities");
    }
    #[test]
    fn serializes_escaped_strings() {
        let app = App {
            id: "a\"b".into(),
            name: "line\nname".into(),
            ..App::default()
        };
        let json = to_json(&[app]);
        assert!(json.contains("a\\\"b"));
        assert!(json.contains("line\\nname"));
    }
}
