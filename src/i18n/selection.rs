//! Resolve desktop language choices without losing region or script information.
//! Qt provides system paths and installs catalogs; selection policy stays in Rust.

use std::{env, fs, path::PathBuf};

const LANGUAGES: &str = include_str!("../../translations/languages.tsv");
#[cfg(test)]
const REGIONS: &str = include_str!("../../translations/regions.tsv");

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Catalog {
    pub name: String,
    pub right_to_left: bool,
}

fn language(code: &str) -> Option<Catalog> {
    LANGUAGES.lines().skip(1).find_map(|row| {
        let fields: Vec<_> = row.split('\t').collect();
        (fields.len() == 5 && fields[0].eq_ignore_ascii_case(code)).then(|| Catalog {
            name: fields[0].into(),
            right_to_left: fields[4] == "RTL",
        })
    })
}

fn normalized_locale(value: &str) -> String {
    let value = value.trim().trim_matches('"').replace('-', "_");
    let (name, modifier) = value.split_once('@').unwrap_or((&value, ""));
    let name = name.split('.').next().unwrap_or_default();
    if modifier.is_empty() {
        name.to_ascii_lowercase()
    } else {
        format!("{name}@{modifier}").to_ascii_lowercase()
    }
}

pub fn catalogs_for_locale(value: &str) -> Vec<Catalog> {
    let normalized = normalized_locale(value);
    if normalized.is_empty() {
        return Vec::new();
    }
    if matches!(normalized.as_str(), "c" | "posix") {
        return vec![language("en").unwrap()];
    }
    let mut parts = normalized.split(['_', '@']);
    let base = parts.next().unwrap_or_default();
    let suffixes: Vec<_> = parts.collect();
    let has = |tag: &str| suffixes.contains(&tag);
    let code = match base {
        "zh" if has("hant") || (!has("hans") && (has("tw") || has("hk") || has("mo"))) => "zh_Hant",
        "zh" => "zh_Hans",
        "sr" if has("latn") || has("latin") => "sr_Latn",
        "sr" => "sr",
        "pa" if has("arab") || has("arabic") || (!has("guru") && has("pk")) => "pa_Arab",
        "pa" => "pa",
        "pnb" => "pa_Arab",
        "ca" if has("valencia") => "ca_valencia",
        "iw" => "he",
        "tl" => "fil",
        "no" => "nb",
        "qu" => "quz",
        // Only Latin-script Kurmanji is in the shared inventory.
        "ku" if has("arab") || has("iq") || has("ir") => return Vec::new(),
        _ => base,
    };
    let Some(base_catalog) = language(code) else {
        return Vec::new();
    };
    let mut result = Vec::new();
    // These are authored wording variants, not copies of every country catalog.
    let regional = match code {
        "de" if has("ch") => Some("de_CH"),
        "pt" if has("br") => Some("pt_BR"),
        _ => None,
    };
    if let Some(name) = regional {
        result.push(Catalog {
            name: name.into(),
            right_to_left: base_catalog.right_to_left,
        });
    }
    result.push(base_catalog);
    result
}

/// Keep each requested language ahead of the next, including its safe fallback.
/// English is an explicit choice, so `en:he` must not silently become Hebrew.
pub fn preferred_catalogs(choices: impl IntoIterator<Item = String>) -> Vec<Catalog> {
    fn script_family(name: &str) -> Option<&str> {
        match name {
            "zh_Hans" | "zh_Hant" => Some("zh"),
            "sr" | "sr_Latn" => Some("sr"),
            "pa" | "pa_Arab" => Some("pa"),
            _ => None,
        }
    }
    let mut result = Vec::new();
    for choice in choices {
        for catalog in catalogs_for_locale(&choice) {
            if let Some(family) = script_family(&catalog.name) {
                if result.iter().any(|earlier: &Catalog| {
                    script_family(&earlier.name) == Some(family) && earlier.name != catalog.name
                }) {
                    continue;
                }
            }
            if !result.contains(&catalog) {
                let english = catalog.name == "en";
                result.push(catalog);
                if english {
                    return result;
                }
            }
        }
    }
    result
}

fn configured_languages(contents: &str) -> Option<&str> {
    let mut translations = false;
    for line in contents.lines() {
        let line = line.trim();
        if line.starts_with('[') && line.ends_with(']') {
            translations = line == "[Translations]";
        } else if translations {
            if let Some((key, value)) = line.split_once('=') {
                if key.trim() == "LANGUAGE" {
                    return Some(value.trim().trim_matches('"'));
                }
            }
        }
    }
    None
}

pub fn application_catalogs(system_languages: Vec<String>) -> Vec<Catalog> {
    let mut choices = Vec::new();
    if let Ok(value) = env::var("LANGUAGE") {
        choices.extend(value.split(':').map(str::to_owned));
    }
    let config_home = env::var_os("XDG_CONFIG_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")));
    if let Some(config_home) = config_home {
        if let Ok(contents) = fs::read_to_string(config_home.join("plasma-localerc")) {
            if let Some(value) = configured_languages(&contents) {
                choices.extend(value.split(':').map(str::to_owned));
            }
        }
    }
    // Read the original POSIX identifier before Qt can drop a glibc modifier or
    // map an unfamiliar language to C. Never modify the system's locale files.
    for variable in ["LC_ALL", "LC_MESSAGES", "LANG"] {
        if let Ok(value) = env::var(variable) {
            if !value.trim().is_empty() {
                choices.push(value);
                break;
            }
        }
    }
    choices.extend(system_languages);
    preferred_catalogs(choices)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(locale: &str) -> Vec<String> {
        catalogs_for_locale(locale)
            .into_iter()
            .map(|catalog| catalog.name)
            .collect()
    }

    #[test]
    fn every_shared_language_and_country_selects_its_catalog() {
        assert_eq!(LANGUAGES.lines().count() - 1, 96);
        assert_eq!(REGIONS.lines().count() - 1, 172);
        for row in REGIONS.lines().skip(1) {
            let fields: Vec<_> = row.split('\t').collect();
            let catalogs = catalogs_for_locale(fields[1]);
            let catalog = catalogs.last().unwrap_or_else(|| panic!("{}", fields[1]));
            assert_eq!(catalog.name, fields[0], "{}", fields[1]);
            assert_eq!(catalog.right_to_left, fields[3] == "RTL", "{}", fields[1]);
        }
        for row in LANGUAGES.lines().skip(1) {
            let fields: Vec<_> = row.split('\t').collect();
            assert_eq!(names(fields[0]).last().unwrap(), fields[0]);
        }
    }

    #[test]
    fn preserves_script_and_glibc_modifiers() {
        for locale in ["sr_RS.UTF-8@latin", "sr-Latn-ME", "sr_Latn"] {
            assert_eq!(names(locale), ["sr_Latn"]);
        }
        for locale in ["sr_RS.UTF-8", "sr-Cyrl-ME"] {
            assert_eq!(names(locale), ["sr"]);
        }
        for locale in ["zh-TW", "zh-Hant-HK", "zh_Hant", "zh_HK.UTF-8"] {
            assert_eq!(names(locale), ["zh_Hant"]);
        }
        for locale in ["zh_CN.UTF-8", "zh-Hans-SG", "zh_Hans"] {
            assert_eq!(names(locale), ["zh_Hans"]);
        }
        for locale in [
            "pa_PK.UTF-8",
            "pa-Arab-PK",
            "pa_Arab",
            "pnb_PK",
            "pa@arabic",
        ] {
            assert_eq!(names(locale), ["pa_Arab"]);
        }
        assert_eq!(names("pa-Guru-IN"), ["pa"]);
        assert_eq!(names("ca_ES.UTF-8@valencia"), ["ca_valencia"]);
        assert!(names("ku_Arab_IQ").is_empty());
        for (first, ambiguous, expected) in [
            ("zh_Hant", "zh", "zh_Hant"),
            ("sr_Latn", "sr", "sr_Latn"),
            ("pa_Arab", "pa", "pa_Arab"),
        ] {
            let catalogs = preferred_catalogs([first.into(), ambiguous.into(), "en".into()]);
            assert_eq!(
                catalogs.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
                [expected, "en"]
            );
        }
    }

    #[test]
    fn regional_wording_falls_back_only_to_its_own_language() {
        assert_eq!(names("de_CH.UTF-8"), ["de_CH", "de"]);
        assert_eq!(names("pt-BR"), ["pt_BR", "pt"]);
        assert_eq!(names("de-AT"), ["de"]);
        assert_eq!(names("fr_CA.UTF-8"), ["fr"]);
        let catalogs = preferred_catalogs(["zh_Hant_HK".into(), "fr_CA".into(), "en".into()]);
        assert_eq!(
            catalogs.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
            ["zh_Hant", "fr", "en"]
        );
    }

    #[test]
    fn explicit_english_stops_later_fallbacks() {
        for english in ["en", "en_US.UTF-8", "en-GB", "C.UTF-8", "POSIX"] {
            assert_eq!(
                preferred_catalogs([english.into(), "he".into()]),
                [language("en").unwrap()]
            );
        }
        assert_eq!(
            preferred_catalogs(["unknown".into(), "he_IL".into()]),
            [language("he").unwrap()]
        );
    }

    #[test]
    fn desktop_language_setting_is_read_from_its_own_group() {
        assert_eq!(
            configured_languages(
                "[Formats]\nLANGUAGE=en\n[Translations]\nLANGUAGE=sr_RS.UTF-8@latin:en\n"
            ),
            Some("sr_RS.UTF-8@latin:en")
        );
        assert_eq!(configured_languages("[Formats]\nLANGUAGE=he\n"), None);
    }
}
