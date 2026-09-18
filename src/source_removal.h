#pragma once
#include "flatpak_sources.h"
#include <QRegularExpression>
#include <QProcess>
#include <QProcessEnvironment>
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
        targets.push_back({std::shared_ptr<FlatpakInstallation>(FLATPAK_INSTALLATION(g_object_ref(installation)),
            [](FlatpakInstallation *item) { g_object_unref(item); }), member});
    }
    return true;
}
inline bool remove(const Target &target, GCancellable *cancel, QString &problem) {
    if (!matches(target.installation.get(), target.expected, problem)) return false;
    if (cancel && g_cancellable_is_cancelled(cancel)) return false;
    // libflatpak's public remove_remote API has no force option. The supported
    // CLI --force removes only the source, skipping its app-uninstall prompt.
    // Always use a fixed executable, explicit installation and separate args.
    const bool user = flatpak_installation_get_is_user(target.installation.get());
    const auto scope = Sources::scope(target.installation.get());
    if (!user && scope.isEmpty()) { problem = "Invalid system installation."; return false; }
    QProcess process;
    auto environment = QProcessEnvironment::systemEnvironment();
    if (user) {
        g_autoptr(GFile) path = flatpak_installation_get_path(target.installation.get());
        g_autofree char *localPath = g_file_get_path(path);
        if (!localPath) { problem = "Invalid user installation."; return false; }
        // Derived from the validated installation, never from request JSON.
        environment.insert("FLATPAK_USER_DIR", Sources::text(localPath));
    }
    process.setProcessEnvironment(environment);
    process.setStandardInputFile(QProcess::nullDevice());
    process.start("/usr/bin/flatpak", {"remote-delete", "--force",
        user ? QString("--user") : "--installation=" + scope,
        "--", target.expected["name"].toString()});
    if (!process.waitForStarted()) { problem = "Could not start Flatpak source removal."; return false; }
    while (!process.waitForFinished(100)) {
        if (cancel && g_cancellable_is_cancelled(cancel)) {
            process.terminate();
            if (!process.waitForFinished(1000)) { process.kill(); process.waitForFinished(1000); }
            return false;
        }
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        problem = QString::fromUtf8(process.readAllStandardError()).trimmed();
        if (problem.isEmpty()) problem = "Could not remove the software source.";
        return false;
    }
    flatpak_installation_drop_caches(target.installation.get(), nullptr, nullptr);
    return true;
}
} // namespace SourceRemoval
