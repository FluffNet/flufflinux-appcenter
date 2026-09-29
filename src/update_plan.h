#pragma once
#include "flatpak_permissions.h"
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>

namespace Updates {
inline QString key(const QString &scope, const QString &ref) { return scope + ":" + ref; }
inline bool validCommit(const QString &commit) {
    return QRegularExpression("^[a-f0-9]{64}$").match(commit).hasMatch();
}
inline QByteArray metadata(GKeyFile *file) {
    if (!file) return {};
    gsize size = 0;
    g_autofree char *data = g_key_file_to_data(file, &size, nullptr);
    return QByteArray(data, size);
}
// Compare permissions, not application/environment metadata (which may contain
// private values). Preserve group order and distinguish additions from removals.
inline QVariantMap permissionChanges(const QByteArray &before, const QByteArray &after) {
    const auto old = AppPermissions::parse(before), next = AppPermissions::parse(after);
    if (old.value("state") != "ready" || next.value("state") != "ready")
        return {{"state", "unknown"}, {"groups", QVariantList{}}};
    QMap<QString, QVariantMap> oldGroups, newGroups;
    QStringList order;
    for (const auto &item : next.value("groups").toList()) {
        const auto group = item.toMap(); const auto id = group.value("id").toString();
        newGroups[id] = group; order.append(id);
    }
    for (const auto &item : old.value("groups").toList()) {
        const auto group = item.toMap(); const auto id = group.value("id").toString();
        oldGroups[id] = group; if (!order.contains(id)) order.append(id);
    }
    QVariantList groups;
    for (const auto &id : order) {
        const auto left = oldGroups.value(id).value("details").toStringList();
        const auto right = newGroups.value(id).value("details").toStringList();
        QStringList added, removed;
        for (const auto &value : right) if (!left.contains(value)) added.append(value);
        for (const auto &value : left) if (!right.contains(value)) removed.append(value);
        if (added.isEmpty() && removed.isEmpty()) continue;
        auto group = newGroups.contains(id) ? newGroups[id] : oldGroups[id];
        group["added"] = added; group["removed"] = removed; group.remove("details");
        groups.append(group);
    }
    return {{"state", groups.isEmpty() ? "unchanged" : "changed"}, {"groups", groups}};
}
// Every resolved operation must still match the plan the user selected. A
// changed source, dependency, or permission-bearing commit requires a recheck.
inline bool matchesPlan(const QJsonArray &expected, const QJsonArray &actual) {
    for (const auto &value : actual) {
        const auto op = value.toObject(); bool found = false;
        for (const auto &allowed : expected) {
            const auto row = allowed.toObject();
            if (row["ref"] == op["ref"] && row["commit"] == op["commit"]
                && row["remote"] == op["remote"] && row["action"] == op["action"]
                && validCommit(op["commit"].toString())) { found = true; break; }
        }
        if (!found) return false;
    }
    return true;
}
}
