use std::collections::BTreeMap;
use std::path::Path;

#[derive(Debug, PartialEq)]
pub enum Command {
    Print(String),
    Launch { actions: Vec<(String, String)>, desktop_file: String },
}

enum ParseError {
    Syntax,
    Rejected(String),
}

// Syntax mistakes become a literal search; resource limits and explicitly
// unsupported operations remain errors rather than being silently swallowed.
impl From<String> for ParseError {
    fn from(_: String) -> Self { Self::Syntax }
}
impl From<&str> for ParseError {
    fn from(_: &str) -> Self { Self::Syntax }
}

pub fn help() -> String {
    format!("App Center {}\n\nUsage: flufflinux-appcenter [options] [SEARCH TEXT, FILES OR URLS…]\n\n\
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
  --                         Stop interpreting options\n\n\
Files: .flatpak, .flatpakref, .flatpakrepo. URLs: appstream:, flatpak:,\n\
https: and flatpak+https:. Relative files resolve in the calling directory.\n\
Options accept --name=value too. Other input is searched as text.\n\
Examples: flufflinux-appcenter telegram; flufflinux-appcenter google chrome\n\
Unrecognized words are joined into one query. Malformed command syntax is\n\
searched literally without executing any partial command.\n\n\
Discover-only --test is not supported: its QML testing framework is different.\n\
--headless-update is not supported; use App Updates to review and install.\n\
Generic Qt configuration can be supplied through QT_QPA_PLATFORM and\n\
QT_QUICK_CONTROLS_STYLE. App Center does not emulate Discover's Qt debug flags.\n",
        include_str!("../VERSION").trim())
}

fn url_scheme(value: &str) -> Option<&str> {
    value.split_once(':').filter(|(prefix, _)| {
        prefix.starts_with(|c: char| c.is_ascii_alphabetic())
            && prefix.chars().all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c))
    }).map(|(scheme, _)| scheme)
}

fn source(value: &str, cwd: &Path, local_only: bool) -> Result<String, String> {
    if value.is_empty() { return Err("A file or URL cannot be empty.".into()); }
    if let Some(scheme) = url_scheme(value) {
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
    match parse_command(args, cwd) {
        Ok(command) => Ok(command),
        Err(ParseError::Rejected(message)) => Err(message),
        Err(ParseError::Syntax) => {
            let query = args.join(" ");
            if query.len() > 8192 { return Err("Search text is too long.".into()); }
            Ok(Command::Launch { actions: vec![("search".into(), query)], desktop_file: "org.kde.discover".into() })
        }
    }
}

fn source_syntax(value: &str) -> bool {
    // Only declared input forms take the file/link path. Ordinary text (even
    // a name containing a colon or a slash) must not become a nonexistent file.
    if let Some(scheme) = url_scheme(value) {
        return ["appstream", "flatpak", "file", "https", "flatpak+https"]
            .iter().any(|candidate| scheme.eq_ignore_ascii_case(candidate));
    }
    Path::new(value).extension().and_then(|part| part.to_str()).is_some_and(|extension|
        ["flatpak", "flatpakref", "flatpakrepo"].iter().any(|candidate| extension.eq_ignore_ascii_case(candidate)))
}

fn parse_command(args: &[String], cwd: &Path) -> Result<Command, ParseError> {
    let mut options = BTreeMap::new();
    let mut positionals = Vec::new();
    let mut words = Vec::new();
    let mut literal = false;
    let mut index = 0;
    while index < args.len() {
        let arg = &args[index];
        index += 1;
        if !literal && arg == "--" { literal = true; continue; }
        if literal || !arg.starts_with('-') {
            if source_syntax(arg) { positionals.push(source(arg, cwd, false)?); }
            else { words.push(arg.clone()); }
            continue;
        }
        let (key, inline) = arg.split_once('=').map_or((arg.as_str(), None), |(k, v)| (k, Some(v)));
        match key {
            "-h" | "--help" | "--help-all" | "-v" | "--version" | "--author" | "--license"
            | "--listmodes" | "--listbackends" | "--updates" | "--headless-update" => {
                if inline.is_some() { return Err(ParseError::Syntax); }
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
                if value.is_empty() && key != "--search" { return Err(ParseError::Syntax); }
                options.insert(key.to_string(), value);
            }
            _ => words.push(arg.clone()),
        }
    }
    let has = |key: &str| options.contains_key(key);
    if has("-h") || has("--help") || has("--help-all") { return Ok(Command::Print(help())); }
    if has("-v") || has("--version") { return Ok(Command::Print(format!("App Center {}\n", include_str!("../VERSION").trim()))); }
    if has("--author") { return Ok(Command::Print("FluffNet LLC\n".into())); }
    if has("--license") { return Ok(Command::Print(include_str!("../LICENSE").into())); }
    if has("--listmodes") { return Ok(Command::Print("Available modes:\n * Browsing\n * Installed\n * Search\n * Update\n * Sources\n * About\n".into())); }
    if has("--listbackends") { return Ok(Command::Print("Available backends:\n * flatpak-backend\n".into())); }
    if has("--headless-update") { return Err(ParseError::Rejected("--headless-update is not supported. Open App Updates with --mode update to review and install updates.".into())); }
    if has("--test") { return Err(ParseError::Rejected("Discover's --test QML framework is not supported by App Center. Use App Center's tests/ and FLUFF_APP_CENTER_QML developer fixtures.".into())); }
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
    if has("--search") || !words.is_empty() {
        let mut query = options.get("--search").cloned().unwrap_or_default();
        if !words.is_empty() {
            if !query.is_empty() { query.push(' '); }
            query.push_str(&words.join(" "));
        }
        if query.len() > 8192 { return Err(ParseError::Rejected("Search text is too long.".into())); }
        actions.push(("search".into(), query));
    }
    if let Some(value) = options.get("--local-filename") { actions.push(("source".into(), source(value, cwd, true)?)); }
    for value in positionals { actions.push(("source".into(), value)); }
    if actions.len() > 16 { return Err(ParseError::Rejected("Open at most 16 files or destinations at once.".into())); }
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
        assert_eq!(actions(&["--mode", "garbage"]), [("search".into(), "--mode garbage".into())]);
    }
    #[test] fn relative_paths_are_resolved_before_ipc() {
        assert_eq!(actions(&["--local-filename", "Space App.flatpakref"])[0].1, "/caller/Space App.flatpakref");
        assert_eq!(actions(&["--", "--updates"]), [("search".into(), "--updates".into())]);
        assert_eq!(actions(&["file:///tmp/App.flatpak"])[0].1, "file:///tmp/App.flatpak");
        assert_eq!(actions(&["--local-filename", "https://example.org/a.flatpakref"])[0].0, "search");
        assert_eq!(actions(&["file:relative.flatpakref"])[0].0, "search");
    }
    #[test] fn application_and_filter_options() {
        assert_eq!(actions(&["--application", "org.Example.App"])[0].1, "appstream:org.Example.App");
        assert_eq!(actions(&["appstream://org.Example.App"])[0].1, "appstream://org.Example.App");
        assert_eq!(actions(&["--mime=application/pdf"])[0].0, "mime");
        assert_eq!(actions(&["--category", "Audio & Video"])[0].1, "Audio & Video");
        assert_eq!(actions(&["--category", "Games", "--search", "chess"]).len(), 2);
    }
    #[test] fn information_options_do_not_launch() {
        assert!(help().contains("Usage: flufflinux-appcenter [options]"));
        for flag in ["-h", "--help", "--help-all", "-v", "--version", "--author", "--license", "--listmodes", "--listbackends"] {
            assert!(matches!(parse_args(&[flag]).unwrap(), Command::Print(_)));
        }
    }
    #[test] fn invalid_unsupported_and_oversized_inputs_fail() {
        for args in [vec!["--headless-update"], vec!["--test", "old.qml"]] {
            assert!(parse_args(&args).is_err(), "{args:?}");
        }
        assert!(parse_args(&vec!["file.flatpak"; 17]).is_err());
        assert!(parse_args(&["--search", &"a".repeat(8193)]).is_err());
        assert!(parse_args(&[&"a".repeat(5000), &"b".repeat(5000)]).is_err());
        assert!(parse_args(&["bad\0input"]).is_err());
    }
    #[test] fn bare_text_and_unknown_options_are_one_search() {
        for (args, expected) in [
            (vec!["telegram"], "telegram"), (vec!["google", "chrome"], "google chrome"),
            (vec!["Google Chrome"], "Google Chrome"), (vec!["משחקים", "chess"], "משחקים chess"),
            (vec!["--serach", "telegram"], "--serach telegram"),
            (vec!["--unknown=value"], "--unknown=value"), (vec!["C++", "music/audio"], "C++ music/audio"),
            (vec!["Steam:", "games"], "Steam: games"), (vec!["org.telegram.desktop"], "org.telegram.desktop"),
            (vec!["--search", "google", "chrome"], "google chrome"),
        ] {
            assert_eq!(actions(&args), [("search".into(), expected.into())], "{args:?}");
        }
    }
    #[test] fn malformed_commands_only_search_never_partially_execute() {
        for args in [vec!["--search"], vec!["--mode", ""], vec!["--help=yes"],
            vec!["--mime", "oops"], vec!["--mime", "application/"], vec!["--desktopfile", "../other"],
            vec!["appstream:org.Example.App", "--mode=nope"], vec!["--updates", "--local-filename"]] {
            assert_eq!(actions(&args), [("search".into(), args.join(" "))], "{args:?}");
        }
    }
    #[test] fn recognized_links_files_and_options_keep_their_meaning() {
        for value in ["appstream://org.Example.App", "flatpak:org.Example.App", "file:///tmp/App.flatpak",
            "https://example.org/App.flatpakref", "flatpak+https://example.org/App.flatpakref"] {
            assert_eq!(actions(&[value]), [("source".into(), value.into())]);
        }
        assert_eq!(actions(&["./My App.FLATPAKREF"]), [("source".into(), "/caller/./My App.FLATPAKREF".into())]);
        assert_eq!(actions(&["./My App:2026.flatpakref"]), [("source".into(), "/caller/./My App:2026.flatpakref".into())]);
        assert_eq!(actions(&["--", "--mode.flatpakref"]), [("source".into(), "/caller/--mode.flatpakref".into())]);
        assert_eq!(actions(&["--mode=Installed", "telegram"]),
            [("mode".into(), "Installed".into()), ("search".into(), "telegram".into())]);
        assert_eq!(actions(&["telegram", "appstream:org.Example.App"]),
            [("search".into(), "telegram".into()), ("source".into(), "appstream:org.Example.App".into())]);
        assert!(actions(&[]).is_empty());
    }
}
