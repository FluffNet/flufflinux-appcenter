#pragma once
#include "flatpak_sources.h"

namespace UpdateSources {
// Restore only a known official channel, never arbitrary user repositories or
// their signing keys into a privileged installation. The caller must first
// establish that installed refs actually use this missing origin.
inline QString restorationDefinition(const QString &scope, const QString &origin,
                                     const QJsonArray &sources) {
    if (scope == "user" || (origin != "flathub" && origin != "flathub-beta")) return {};
    for (const auto &value : sources) {
        const auto source = value.toObject();
        const auto installedScope = source["scope"].toString();
        if ((installedScope == scope || (scope == "system" && installedScope == "default"))
            && source["name"] == origin) return {}; // Never replace or re-enable an existing source.
    }
    const auto definition = origin == "flathub"
        ? QString("https://dl.flathub.org/repo/flathub.flatpakrepo")
        : QString("https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo");
    for (const auto &value : sources) {
        const auto source = value.toObject();
        if (source["scope"] == "user" && source["name"] == origin
            && source["enabled"].toBool() && source["verified"].toBool()
            && Sources::officialDefinition(source["url"].toString()) == definition) return definition;
    }
    return {};
}
inline QStringList restoreArguments(const QString &scope, const QString &origin, const QString &definition) {
    return {scope == "system" ? "--system" : "--installation=" + scope,
        "remote-add", "--if-not-exists", "--from", origin, definition};
}
}
