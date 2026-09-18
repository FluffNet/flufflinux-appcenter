#pragma once
#include "flatpak_sources.h"
#include <QRegularExpression>
#include <memory>
#include <vector>

namespace SourceRemoval {
struct Target {
    std::shared_ptr<FlatpakInstallation> installation;
    QJsonObject expected;
};
inline bool matches(FlatpakInstallation *installation, const QJsonObject &expected, QString &problem) {
    static const QRegularExpression namePattern("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,254}$");
    const auto name = expected["name"].toString();
    if (!namePattern.match(name).hasMatch()) { problem = "Invalid software-source name."; return false; }
    if (!flatpak_installation_drop_caches(installation, nullptr, nullptr)) {
        problem = "Could not re-read the software source safely."; return false;
    }
    g_autoptr(GError) lookupError = nullptr;
    // get_remote_by_name can invoke Flatpak's system EnsureRepo helper even
    // for a read. Enumeration keeps validation unprivileged; only our explicit
    // system-removal helper may request administrator authorization.
    g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(installation, nullptr, &lookupError);
    FlatpakRemote *remote = nullptr;
    for (guint i = 0; remotes && i < remotes->len; ++i) {
        auto candidate = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
        if (Sources::text(flatpak_remote_get_name(candidate)) == name) remote = candidate;
    }
    if (!remote) {
        problem = "Could not read source " + name + " (" + Sources::scope(installation) + "): "
            + Sources::text(lookupError ? lookupError->message : "source not found"); return false;
    }
    if (Sources::url(remote) != expected["url"].toString()) {
        problem = "The address of " + name + " changed. Refresh Settings before removing it."; return false;
    }
    if (Sources::sourceKey(installation, remote) != expected["sourceKey"].toString()) {
        problem = "The signing keys or settings of " + name + " changed. Refresh Settings before removing it."; return false;
    }
    return true;
}
inline bool unused(FlatpakInstallation *installation, const QString &name, QString &problem) {
    g_autoptr(GError) error = nullptr;
    g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs(installation, nullptr, &error);
    if (!refs) { problem = Sources::text(error->message); return false; }
    for (guint i = 0; i < refs->len; ++i) {
        auto ref = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, i));
        if (Sources::text(flatpak_installed_ref_get_origin(ref)) == name) {
            problem = "The source " + name + " is still used by installed apps or runtimes. No sources were removed.";
            return false;
        }
    }
    return true;
}
inline bool resolve(FlatpakInstallation *user, const QJsonArray &members, bool systemOnly,
                    std::vector<Target> &targets, QString &problem) {
    if (members.isEmpty() || members.size() > 32) { problem = "Invalid source-removal request."; return false; }
    g_autoptr(GError) error = nullptr;
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, &error);
    if (!systems) { problem = Sources::text(error->message); return false; }
    QSet<QString> seen;
    for (const auto &entry : members) {
        const auto member = entry.toObject();
        const auto scope = member["scope"].toString();
        FlatpakInstallation *installation = nullptr;
        if (scope == "user" && !systemOnly) installation = user;
        else if (scope != "user") for (guint i = 0; i < systems->len; ++i) {
            auto candidate = FLATPAK_INSTALLATION(g_ptr_array_index(systems, i));
            if (Sources::scope(candidate) == scope) installation = candidate;
        }
        const auto identity = scope + ":" + member["name"].toString();
        if (!installation || scope.isEmpty() || seen.contains(identity)) { problem = "Invalid source-removal target."; return false; }
        seen.insert(identity);
        if (!matches(installation, member, problem)) return false;
        // System preflight runs inside the authorized helper. User preflight
        // happens before the prompt, so a rejected user copy cannot cause a
        // partial system removal.
        if ((systemOnly || scope == "user") && !unused(installation, member["name"].toString(), problem)) return false;
        targets.push_back({std::shared_ptr<FlatpakInstallation>(FLATPAK_INSTALLATION(g_object_ref(installation)),
            [](FlatpakInstallation *item) { g_object_unref(item); }), member});
    }
    return true;
}
inline bool remove(const Target &target, GCancellable *cancel, QString &problem) {
    if (!matches(target.installation.get(), target.expected, problem)) return false;
    g_autoptr(GError) error = nullptr;
    if (!flatpak_installation_remove_remote(target.installation.get(), target.expected["name"].toString().toUtf8(), cancel, &error)) {
        problem = Sources::text(error->message); return false;
    }
    return true;
}
} // namespace SourceRemoval
