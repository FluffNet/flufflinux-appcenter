#pragma once
#include <flatpak.h>
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QSet>

// Only AppStream add-ons that Flatpak also relates to the installed parent
// are actionable. Runtime IDs, branches and installation scopes are not guessed.
namespace AppAddons {
inline QString text(const char *value) { return QString::fromUtf8(value ? value : ""); }
inline QJsonObject error(const QString &message) { return {{"state", "error"}, {"error", message}}; }
inline QJsonObject compactParent(const QJsonObject &input) {
    QJsonObject parent;
    for (const auto key : {"installedRef", "installation", "sourceUrl", "parentCommit", "remote"})
        parent[key] = input[key];
    QJsonArray addons;
    for (const auto &entry : input["addons"].toArray()) {
        QJsonObject row;
        for (const auto key : {"id", "name", "summary", "developer", "icon", "flatpakRef", "sourceUrl"}) row[key] = entry.toObject()[key];
        addons.append(row);
    }
    parent["addons"] = addons;
    return parent;
}
inline FlatpakInstallation *installation(const QString &scope, GCancellable *cancel) {
    return scope == "user" ? flatpak_installation_new_user(cancel, nullptr)
        : scope == "system" ? flatpak_installation_new_system(cancel, nullptr)
        : flatpak_installation_new_system_with_id(scope.toUtf8(), cancel, nullptr);
}
inline QJsonObject read(QJsonObject parent, GCancellable *cancel = nullptr, bool installedOnly = false) {
    parent = compactParent(parent);
    const auto scope = parent["installation"].toString();
    if (scope.isEmpty()) return {{"state", "not-installed"}, {"items", parent["addons"].toArray()}};
    const auto fullRef = parent["installedRef"].toString();
    g_autoptr(FlatpakRef) parsed = flatpak_ref_parse(fullRef.toUtf8(), nullptr);
    if (!parsed || flatpak_ref_get_kind(parsed) != FLATPAK_REF_KIND_APP)
        return error(QCoreApplication::translate("Addons", "The parent app is no longer available. Reopen its page."));
    g_autoptr(FlatpakInstallation) instance = installation(scope, cancel);
    if (!instance) return error(QCoreApplication::translate("Addons", "Could not open this Flatpak installation."));
    g_autoptr(FlatpakInstalledRef) installed = flatpak_installation_get_installed_ref(instance, FLATPAK_REF_KIND_APP,
        flatpak_ref_get_name(parsed), flatpak_ref_get_arch(parsed), flatpak_ref_get_branch(parsed), cancel, nullptr);
    if (!installed) return {{"state", "not-installed"}, {"items", parent["addons"].toArray()}};
    const auto commit = text(flatpak_ref_get_commit(FLATPAK_REF(installed)));
    if (!parent["parentCommit"].toString().isEmpty() && parent["parentCommit"].toString() != commit)
        return error(QCoreApplication::translate("Addons", "The app changed. Reopen Add-Ons before continuing."));
    const auto origin = text(flatpak_installed_ref_get_origin(installed));
    g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(instance, origin.toUtf8(), cancel, nullptr);
    g_autofree char *url = remote ? flatpak_remote_get_url(remote) : nullptr;
    if (!remote || text(url) != parent["sourceUrl"].toString())
        return error(QCoreApplication::translate("Addons", "This app's source is unavailable or has changed. Refresh its page."));
    parent["parentCommit"] = commit;
    parent["remote"] = origin;
    QMap<QString, bool> refs;
    g_autoptr(GPtrArray) local = flatpak_installation_list_installed_related_refs_sync(instance,
        origin.toUtf8(), fullRef.toUtf8(), cancel, nullptr);
    for (guint i = 0; local && i < local->len; ++i) {
        g_autofree char *ref = flatpak_ref_format_ref(FLATPAK_REF(g_ptr_array_index(local, i)));
        refs.insert(text(ref), false);
    }
    g_autoptr(GError) failure = nullptr;
    g_autoptr(GPtrArray) available = !installedOnly && !flatpak_remote_get_disabled(remote)
        ? flatpak_installation_list_remote_related_refs_for_installed_sync(instance,
            origin.toUtf8(), fullRef.toUtf8(), cancel, &failure) : nullptr;
    for (guint i = 0; available && i < available->len; ++i) {
        g_autofree char *ref = flatpak_ref_format_ref(FLATPAK_REF(g_ptr_array_index(available, i)));
        refs.insert(text(ref), true);
    }
    QJsonArray rows;
    QSet<QString> seen;
    for (const auto &candidate : parent["addons"].toArray()) {
        const auto metadata = candidate.toObject();
        g_autoptr(FlatpakRef) candidateRef = flatpak_ref_parse(metadata["flatpakRef"].toString().toUtf8(), nullptr);
        if (!candidateRef || flatpak_ref_get_kind(candidateRef) != FLATPAK_REF_KIND_RUNTIME) continue;
        for (auto entry = refs.cbegin(); entry != refs.cend(); ++entry) {
            g_autoptr(FlatpakRef) ref = flatpak_ref_parse(entry.key().toUtf8(), nullptr);
            if (!ref || flatpak_ref_get_kind(ref) != FLATPAK_REF_KIND_RUNTIME
                || text(flatpak_ref_get_name(ref)) != text(flatpak_ref_get_name(candidateRef))
                || text(flatpak_ref_get_arch(ref)) != text(flatpak_ref_get_arch(parsed))) continue;
            g_autoptr(FlatpakInstalledRef) current = flatpak_installation_get_installed_ref(instance,
                FLATPAK_REF_KIND_RUNTIME, flatpak_ref_get_name(ref), flatpak_ref_get_arch(ref),
                flatpak_ref_get_branch(ref), cancel, nullptr);
            if (current && text(flatpak_installed_ref_get_origin(current)) != origin) continue;
            if (seen.contains(entry.key())) continue;
            seen.insert(entry.key());
            auto row = metadata;
            row["id"] = text(flatpak_ref_get_name(ref)); row["flatpakRef"] = entry.key();
            row["installed"] = bool(current); row["available"] = entry.value();
            row["installation"] = scope; row["remote"] = origin; row["addon"] = true;
            row["installedArch"] = text(flatpak_ref_get_arch(ref));
            row["installedBranch"] = text(flatpak_ref_get_branch(ref));
            rows.append(row);
        }
    }
    return {{"state", "ready"}, {"parent", parent}, {"items", rows},
        {"error", failure ? QCoreApplication::translate("Addons", "Could not check available add-ons. Installed add-ons are still shown.") : QString()}};
}
inline bool validate(const QJsonObject &request, GCancellable *cancel, QString &problem) {
    const bool removing = request["action"].toString() == "uninstall";
    const auto result = read(request["parent"].toObject(), cancel, removing);
    for (const auto &entry : result["items"].toArray()) {
        const auto row = entry.toObject();
        if (result["state"] == "ready" && row["flatpakRef"] == request["flatpakRef"]
            && row["installation"] == request["installation"] && row["remote"] == request["remote"]
            && row["id"] == request["id"] && row[removing ? "installed" : "available"].toBool()) return true;
    }
    problem = result["error"].toString();
    if (problem.isEmpty()) problem = QCoreApplication::translate("Addons", "This add-on is no longer compatible or available. Reopen Add-Ons.");
    return false;
}
}
