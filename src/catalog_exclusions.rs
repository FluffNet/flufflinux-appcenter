use std::collections::HashSet;
use std::fs;

#[derive(Default)]
pub struct Exclusions {
    exact: HashSet<String>,
    prefixes: HashSet<String>,
}

fn normalize(id: &str) -> &str {
    if id.get(id.len().saturating_sub(8)..).is_some_and(|suffix| suffix.eq_ignore_ascii_case(".desktop")) {
        &id[..id.len() - 8]
    } else { id }
}

fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.contains('.') && id.len() <= 255
        && id.bytes().all(|c| c.is_ascii_alphanumeric() || b"._-".contains(&c))
        && id.split('.').all(|part| !part.is_empty())
}

impl Exclusions {
    pub fn matches_id(&self, id: &str) -> bool {
        let canonical_id = normalize(id).to_ascii_lowercase();
        let id = id.to_ascii_lowercase();
        self.exact.contains(&canonical_id) || self.prefixes.iter().any(|prefix| id.starts_with(prefix))
    }

    pub fn should_hide(&self, appstream_id: &str, flatpak_ref: &str,
                       is_installed: impl Fn(&str) -> bool) -> bool {
        // Flatpak bundle IDs and AppStream IDs can differ. Match either ID,
        // never a display name, and use the bundle ID for the installed check.
        let parts: Vec<_> = flatpak_ref.split('/').collect();
        let bundle_id = (parts.len() == 4 && parts[0] == "app" && valid_id(parts[1])
            && !parts[2].is_empty() && !parts[3].is_empty()).then(|| parts[1]);
        let excluded = self.matches_id(appstream_id)
            || bundle_id.is_some_and(|id| self.matches_id(id));
        excluded && !is_installed(normalize(bundle_id.unwrap_or(appstream_id)))
    }
}

pub fn parse(text: &str) -> Exclusions {
    let mut rules = Exclusions::default();
    for line in text.lines() {
        let rule = line.split('#').next().unwrap_or_default().trim();
        let prefix = rule.ends_with('*');
        let id = if prefix { rule.strip_suffix('*').unwrap() } else { normalize(rule) };
        // Only exact IDs or a single trailing '*' are supported. Never treat
        // an invalid rule, bare '*', name, regex or substring as an exclusion.
        if !valid_id(id) { continue; }
        if prefix { rules.prefixes.insert(id.to_ascii_lowercase()); }
        else { rules.exact.insert(id.to_ascii_lowercase()); }
    }
    rules
}

pub fn load() -> Exclusions {
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
        assert_eq!(values.exact.len(), 2);
        assert!(values.prefixes.is_empty());
        assert!(values.matches_id("org.videolan.VLC"));
        assert!(values.matches_id("org.videolan.VLC.desktop"));
        assert!(!values.matches_id("org.videolan.VLC.Plugin"));
        assert!(values.matches_id("org.videolan.vlc"));
        assert!(parse("").exact.is_empty());
    }
    #[test]
    fn bundled_defaults_only_exclude_system_supplied_apps() {
        let defaults = parse(include_str!("../data/exclusions.conf"));
        for id in ["org.videolan.VLC", "org.libreoffice.LibreOffice", "org.winehq.Wine",
            "org.winehq.Wine.DLLs", "com.fightcade.Fightcade.wine", "org.kde.dolphin.desktop",
            "org.kde.konsole.desktop", "org.mozilla.Thunderbird", "org.kde.kate.desktop",
            "org.kde.kwrite.desktop", "io.missioncenter.MissionCenter", "org.kde.ark.desktop",
            "org.kde.gwenview.desktop"] {
            assert!(defaults.matches_id(id), "Missing exclusion: {id}");
        }
        for id in ["com.discordapp.Discord", "com.valvesoftware.Steam", "org.mozilla.firefox",
            "org.kde.kdenlive", "com.fightcade.Fightcade", "org.example.Wine"] {
            assert!(!defaults.matches_id(id), "Unrelated app excluded: {id}");
        }
    }
    #[test]
    fn trailing_wildcards_match_id_prefixes_only() {
        let rules = parse(" org.winehq.Wine* # ID prefix\norg.winehq.Wine*\r\norg.kde.kate.desktop\n");
        assert_eq!(rules.prefixes.len(), 1);
        for id in ["org.winehq.Wine", "org.winehq.Wine.desktop", "org.winehq.WineBeta", "org.winehq.Wine.gecko", "org.winehq.wine"] {
            assert!(rules.matches_id(id));
        }
        for id in ["Wine", "com.example.org.winehq.Wine", "org.kde.kate.Plugin"] {
            assert!(!rules.matches_id(id));
        }
        assert!(rules.matches_id("org.kde.kate"));
        let desktop_prefix = parse("org.kde.kate.desktop*");
        assert!(desktop_prefix.matches_id("org.kde.kate.desktop.Plugin"));
        assert!(!desktop_prefix.matches_id("org.kde.kate.Other"), "Do not broaden a literal ID prefix");
    }
    #[test]
    fn case_insensitive_ids_prefixes_and_desktop_aliases() {
        let rules = parse("ORG.KDE.KATE.DESKTOP\norg.kde.kate\nORG.WINEHQ.WINE*\norg.winehq.wine*\n");
        assert_eq!(rules.exact.len(), 1);
        assert_eq!(rules.prefixes.len(), 1);
        for id in ["org.kde.kate", "OrG.KdE.KaTe.Desktop", "org.winehq.Wine", "ORG.WINEHQ.WINE.Gecko"] {
            assert!(rules.matches_id(id), "Case-insensitive ID match: {id}");
        }
        assert!(!rules.matches_id("org.kde.kate.Plugin"));
        assert!(!rules.should_hide("org.winehq.WINE.desktop", "app/org.winehq.Wine/x86_64/stable",
            |id| id == "org.winehq.Wine"), "Installed lookup retains the actual Flatpak ID spelling");
    }
    #[test]
    fn invalid_patterns_never_turn_into_broad_rules() {
        let rules = parse("*\norg.*.Wine\n*.Wine\norg.winehq.Wine**\nWine\nWine emulator\norg.example.?\norg..example\n.org.example\norg.example.\n");
        assert!(rules.exact.is_empty() && rules.prefixes.is_empty());
        assert!(!rules.matches_id("org.winehq.Wine"));
        assert!(!parse(&format!("org.example.{}*", "x".repeat(256))).matches_id("org.example.App"));
    }
    #[test]
    fn bundle_identity_and_installed_exception() {
        let rules = parse("org.example.Flatpak*\norg.example.Metadata.desktop\n");
        let reference = "app/org.example.Flatpak/x86_64/stable";
        assert!(rules.should_hide("org.other.Metadata", reference, |_| false));
        assert!(!rules.should_hide("org.other.Metadata", reference, |id| id == "org.example.Flatpak"));
        assert!(rules.should_hide("org.example.Metadata.desktop", "app/org.other.App/x86_64/beta", |_| false));
        assert!(!rules.should_hide("org.example.Metadata.desktop", "app/org.other.App/x86_64/beta", |id| id == "org.other.App"));
        assert!(!rules.should_hide("org.example.Metadata.desktop", "", |id| id == "org.example.Metadata"));
        assert!(!rules.should_hide("org.other.App", "runtime/org.example.Flatpak/x86_64/stable", |_| false));
        assert!(!rules.should_hide("org.other.App", "app/org.example.Flatpak", |_| false));
        assert!(!rules.should_hide("org.other.App", "app/org.other.App/x86_64/stable", |_| panic!("Unmatched app needs no installed check")));
    }
}
