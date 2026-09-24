use std::collections::HashSet;
use std::fs;

pub fn parse(text: &str) -> HashSet<String> {
    text.lines().filter_map(|line| {
        let id = line.split('#').next().unwrap_or_default().trim();
        let id = id.strip_suffix(".desktop").unwrap_or(id);
        // Exact identifiers only: no wildcards or accidental description matching.
        (!id.is_empty() && id.contains('.') && id.len() <= 255
            && id.bytes().all(|c| c.is_ascii_alphanumeric() || b"._-".contains(&c)))
            .then(|| id.to_string())
    }).collect()
}

pub fn load() -> HashSet<String> {
    let path = std::env::var_os("FLUFF_APP_CENTER_EXCLUSIONS")
        .unwrap_or_else(|| "/etc/flufflinux-appcenter/exclusions.conf".into());
    // An existing empty file intentionally disables the defaults.
    let text = fs::read_to_string(path).unwrap_or_else(|_| include_str!("../data/exclusions.conf").to_string());
    parse(&text)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_ids_comments_duplicates_and_desktop_aliases() {
        let values = parse("# Comment\norg.videolan.VLC\norg.videolan.VLC.desktop # Same app\n\norg.example.Other\n*.bad\nnot an app\n");
        assert_eq!(values.len(), 2);
        assert!(values.contains("org.videolan.VLC"));
        assert!(!values.contains("org.videolan.VLC.Plugin"));
        assert!(parse("").is_empty());
    }
    #[test]
    fn bundled_defaults_only_exclude_system_supplied_apps() {
        let defaults = parse(include_str!("../data/exclusions.conf"));
        assert!(defaults.contains("org.videolan.VLC"));
        assert!(defaults.contains("org.libreoffice.LibreOffice"));
        assert!(!defaults.contains("com.discordapp.Discord"));
    }
}
