use std::collections::BTreeMap;
use std::path::Path;

#[derive(Debug, PartialEq)]
pub enum Command {
    Print(String),
    Launch { actions: Vec<(String, String)>, desktop_file: String },
}

pub fn help() -> String {
    format!("App Center {}\n\nUsage: app-center [options] [FILES OR URLS…]\n\n\
Options (also supported by plasma-discover, discover and flufflinux-discover):\n\
  --search <text>             Open global app search\n\
  --application <ID or URI>    Open an app by ID or appstream: URI\n\
  --category <name>           Browse a category or AppStream category ID\n\
  --mime <type>               Find apps declaring support for a MIME type\n\
  --mode <name>               Browsing, Installed, Search, Update, Sources, About\n\
  --updates                  Open App Updates (does not check automatically)\n\
  --listmodes                 Print the supported modes\n\
  --listbackends              Print the available backend\n\
  --local-filename <file>     Review a local Flatpak file (does not install it)\n\
  --desktopfile <name>        Override the desktop ID for a new window\n\
  --catalog                  Print the local catalog as JSON\n\
  -h, --help, --help-all      Show this help\n\
  -v, --version              Show version\n\
  --author                   Show author\n\
  --license                  Show license\n\
  --                         Treat remaining arguments as files or URLs\n\n\
Files: .flatpak, .flatpakref, .flatpakrepo. URLs: appstream:, flatpak:,\n\
https: and flatpak+https:. Relative files resolve in the calling directory.\n\
Options accept --name=value too. Search text containing spaces must be quoted.\n\n\
Discover-only --test is not supported: its QML testing framework is different.\n\
--headless-update is not supported; use App Updates to review and install.\n\
Generic Qt configuration can be supplied through QT_QPA_PLATFORM and\n\
QT_QUICK_CONTROLS_STYLE. App Center does not emulate Discover's Qt debug flags.\n",
        include_str!("../VERSION").trim())
}

fn source(value: &str, cwd: &Path, local_only: bool) -> Result<String, String> {
    if value.is_empty() { return Err("A file or URL cannot be empty.".into()); }
    let scheme = value.split_once(':').filter(|(prefix, _)| {
        prefix.starts_with(|c: char| c.is_ascii_alphabetic())
            && prefix.chars().all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c))
    });
    if let Some((scheme, _)) = scheme {
        if scheme.eq_ignore_ascii_case("file") && !value[scheme.len() + 1..].starts_with('/') {
            return Err("Use an absolute file: URL or a plain relative file path.".into());
        }
        if local_only && !scheme.eq_ignore_ascii_case("file") {
            return Err("--local-filename requires a local file, not a remote URL.".into());
        }
        return Ok(value.into());
    }
    Ok(cwd.join(value).to_string_lossy().into_owned())
}

fn mode(value: &str) -> Result<String, String> {
    Ok(match value.to_ascii_lowercase().as_str() {
        "browsing" | "home" => "Browsing",
        "installed" => "Installed",
        "search" => "Search",
        "update" | "updates" => "Update",
        "sources" | "settings" => "Sources",
        "about" => "About",
        _ => return Err(format!("Unknown mode '{value}'. Use --listmodes.")),
    }.into())
}

pub fn parse(args: &[String], cwd: &Path) -> Result<Command, String> {
    if args.iter().any(|arg| arg.len() > 8192 || arg.contains('\0')) || args.len() > 64 {
        return Err("Too many or oversized command-line arguments.".into());
    }
    let mut options = BTreeMap::new();
    let mut positionals = Vec::new();
    let mut literal = false;
    let mut index = 0;
    while index < args.len() {
        let arg = &args[index];
        index += 1;
        if literal { positionals.push(source(arg, cwd, false)?); continue; }
        if arg == "--" { literal = true; continue; }
        if !arg.starts_with('-') { positionals.push(source(arg, cwd, false)?); continue; }
        let (key, inline) = arg.split_once('=').map_or((arg.as_str(), None), |(k, v)| (k, Some(v)));
        match key {
            "-h" | "--help" | "--help-all" | "-v" | "--version" | "--author" | "--license"
            | "--listmodes" | "--listbackends" | "--updates" | "--headless-update" => {
                if inline.is_some() { return Err(format!("{key} does not take a value.")); }
                options.insert(key.to_string(), String::new());
            }
            "--search" | "--application" | "--mime" | "--category" | "--mode" | "--local-filename"
            | "--desktopfile" | "--test" => {
                let value = match inline {
                    Some(value) => value.to_string(),
                    None => {
                        let value = args.get(index).filter(|v| !v.starts_with("--"))
                            .ok_or_else(|| format!("{key} requires a value."))?;
                        index += 1;
                        value.clone()
                    }
                };
                if value.is_empty() && key != "--search" { return Err(format!("{key} requires a non-empty value.")); }
                options.insert(key.to_string(), value);
            }
            _ => return Err(format!("Unknown option '{key}'. Use --help.")),
        }
    }
    let has = |key: &str| options.contains_key(key);
    if has("-h") || has("--help") || has("--help-all") { return Ok(Command::Print(help())); }
    if has("-v") || has("--version") { return Ok(Command::Print(format!("App Center {}\n", include_str!("../VERSION").trim()))); }
    if has("--author") { return Ok(Command::Print("FluffNet LLC\n".into())); }
    if has("--license") { return Ok(Command::Print(include_str!("../LICENSE").into())); }
    if has("--listmodes") { return Ok(Command::Print("Available modes:\n * Browsing\n * Installed\n * Search\n * Update\n * Sources\n * About\n".into())); }
    if has("--listbackends") { return Ok(Command::Print("Available backends:\n * flatpak-backend\n".into())); }
    if has("--headless-update") { return Err("--headless-update is not supported. Open App Updates with --mode update to review and install updates.".into()); }
    if has("--test") { return Err("Discover's --test QML framework is not supported by App Center. Use App Center's tests/ and FLUFF_APP_CENTER_QML developer fixtures.".into()); }
    let desktop_file = options.get("--desktopfile").map(|name| name.trim_end_matches(".desktop")).unwrap_or("org.kde.discover");
    if desktop_file.is_empty() || !desktop_file.chars().all(|c| c.is_ascii_alphanumeric() || "._-".contains(c)) {
        return Err("--desktopfile requires a desktop-entry base name, not a path.".into());
    }
    let mut actions = Vec::new();
    // Match Discover's priority for competing initial destinations.
    if let Some(value) = options.get("--application") {
        let value = if value.contains(':') { value.clone() } else { format!("appstream:{value}") };
        actions.push(("source".into(), value));
    } else if let Some(value) = options.get("--mime") {
        if !value.contains('/') || value.split('/').count() != 2 || value.starts_with('/') || value.ends_with('/')
            || !value.chars().all(|c| c.is_ascii_alphanumeric() || "/.+_-".contains(c)) {
            return Err("--mime requires a MIME type such as application/pdf.".into());
        }
        actions.push(("mime".into(), value.to_ascii_lowercase()));
    } else if let Some(value) = options.get("--category") {
        actions.push(("category".into(), value.clone()));
    } else if has("--updates") || has("--mode") {
        actions.push(("mode".into(), mode(if has("--updates") { "update" } else { &options["--mode"] })?));
    }
    if let Some(value) = options.get("--search") { actions.push(("search".into(), value.clone())); }
    if let Some(value) = options.get("--local-filename") { actions.push(("source".into(), source(value, cwd, true)?)); }
    for value in positionals { actions.push(("source".into(), value)); }
    if actions.len() > 16 { return Err("Open at most 16 files or destinations at once.".into()); }
    Ok(Command::Launch { actions, desktop_file: desktop_file.into() })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn parse_args(args: &[&str]) -> Result<Command, String> {
        parse(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>(), Path::new("/caller"))
    }
    fn actions(args: &[&str]) -> Vec<(String, String)> {
        let Command::Launch { actions, .. } = parse_args(args).unwrap() else { panic!("Not a launch") };
        actions
    }
    #[test] fn search_and_equals_preserve_literal_text() {
        for args in [vec!["--search", "Telegram & friends"], vec!["--search=Telegram & friends"]] {
            assert_eq!(actions(&args), [("search".into(), "Telegram & friends".into())]);
        }
        assert_eq!(actions(&["--search", "a", "--search", "b"])[0].1, "b");
        assert_eq!(actions(&["--search=--mode"])[0].1, "--mode");
    }
    #[test] fn legacy_modes_are_case_insensitive() {
        for value in ["browsing", "Installed", "SEARCH", "update", "Sources", "about"] {
            assert!(parse_args(&["--mode", value]).is_ok());
        }
        for args in [vec!["--updates"], vec!["--mode", "update"], vec!["--mode=update"]] {
            assert_eq!(actions(&args), [("mode".into(), "Update".into())]);
        }
        assert!(parse_args(&["--mode", "garbage"]).is_err());
    }
    #[test] fn relative_paths_are_resolved_before_ipc() {
        assert_eq!(actions(&["--local-filename", "Space App.flatpakref"])[0].1, "/caller/Space App.flatpakref");
        assert_eq!(actions(&["--", "--updates"])[0].1, "/caller/--updates");
        assert_eq!(actions(&["file:///tmp/App.flatpak"])[0].1, "file:///tmp/App.flatpak");
        assert!(parse_args(&["--local-filename", "https://example.org/a.flatpakref"]).is_err());
        assert!(parse_args(&["file:relative.flatpakref"]).is_err());
    }
    #[test] fn application_and_filter_options() {
        assert_eq!(actions(&["--application", "org.Example.App"])[0].1, "appstream:org.Example.App");
        assert_eq!(actions(&["appstream://org.Example.App"])[0].1, "appstream://org.Example.App");
        assert_eq!(actions(&["--mime=application/pdf"])[0].0, "mime");
        assert_eq!(actions(&["--category", "Audio & Video"])[0].1, "Audio & Video");
        assert_eq!(actions(&["--category", "Games", "--search", "chess"]).len(), 2);
    }
    #[test] fn information_options_do_not_launch() {
        for flag in ["-h", "--help", "--help-all", "-v", "--version", "--author", "--license", "--listmodes", "--listbackends"] {
            assert!(matches!(parse_args(&[flag]).unwrap(), Command::Print(_)));
        }
    }
    #[test] fn invalid_unsupported_and_oversized_inputs_fail() {
        for args in [vec!["--search"], vec!["--unknown"], vec!["--mode", ""], vec!["--help=yes"],
            vec!["--mime", "oops"], vec!["--mime", "application/"], vec!["--desktopfile", "../other"],
            vec!["--headless-update"], vec!["--test", "old.qml"]] {
            assert!(parse_args(&args).is_err(), "{args:?}");
        }
        assert!(parse_args(&vec!["file.flatpak"; 17]).is_err());
        assert!(parse_args(&["--search", &"a".repeat(8193)]).is_err());
    }
}
