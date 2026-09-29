#pragma once
#include "flatpak_sources.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QFileInfo>

// Fingerprint local inputs without decompressing AppStream or enumerating the
// thousands of remote refs. No network requests or remote refreshes occur here.
namespace CatalogInputs {
inline QJsonArray stamp(const QString &path) {
    const QFileInfo file(path);
    return {file.absoluteFilePath(), file.canonicalFilePath(), file.exists(), double(file.size()),
        double(file.lastModified().toMSecsSinceEpoch()), double(file.metadataChangeTime().toMSecsSinceEpoch())};
}
inline QString contents(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly)
        ? QString::fromLatin1(QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha256).toHex())
        : QStringLiteral("unreadable");
}
inline void catalogFiles(QJsonArray &inputs, const QString &path, int depth = 0) {
    if (depth > 5) return;
    const auto active = path + "/active";
    if (QFileInfo::exists(active + "/appstream.xml.gz") || QFileInfo::exists(active + "/appstream.xml")) {
        // Flatpak deployments are immutable. The active target and XML stamps
        // cover a new deployment without walking thousands of cached icons.
        inputs.append(stamp(active + "/appstream.xml.gz"));
        inputs.append(stamp(active + "/appstream.xml"));
        return;
    }
    // Match the parser's XML/gzip selection, including nonstandard catalogs.
    for (const auto &file : QDir(path).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        if (file.isDir()) catalogFiles(inputs, file.absoluteFilePath(), depth + 1);
        else if (file.suffix() == "xml" || file.suffix() == "gz") inputs.append(stamp(file.absoluteFilePath()));
    }
}
inline bool installation(QJsonArray &inputs, FlatpakInstallation *installation) {
    g_autofree char *location = g_file_get_path(flatpak_installation_get_path(installation));
    const auto path = Sources::text(location);
    inputs.append(path);
    inputs.append(contents(path + "/repo/config"));
    inputs.append(stamp(path + "/.changed"));
    // Config, external filters and keys govern which sources can be browsed.
    for (const auto &file : QDir(path + "/repo").entryInfoList({"*.gpg"}, QDir::Files, QDir::Name))
        inputs.append(stamp(file.absoluteFilePath()));
    g_autoptr(GError) error = nullptr;
    g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(installation, nullptr, &error);
    if (error) return false;
    for (guint i = 0; remotes && i < remotes->len; ++i) {
        auto remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
        g_autofree char *filter = flatpak_remote_get_filter(remote);
        inputs.append(QJsonArray{Sources::text(flatpak_remote_get_name(remote)), Sources::text(filter),
            filter ? contents(Sources::text(filter)) : QString()});
        g_autoptr(GFile) directory = flatpak_remote_get_appstream_dir(remote, nullptr);
        if (!directory) continue;
        g_autofree char *root = g_file_get_path(directory);
        catalogFiles(inputs, Sources::text(root));
    }
    // Cached summaries supply catalog sizes; deployment changes affect the
    // installed-app exception to exclusions. Neither lookup fetches anything.
    for (const auto &file : QDir(path + "/repo/tmp/cache/summaries").entryInfoList(QDir::Files, QDir::Name))
        inputs.append(stamp(file.absoluteFilePath()));
    g_autoptr(GPtrArray) installed = flatpak_installation_list_installed_refs(installation, nullptr, &error);
    if (error) return false;
    QStringList deployments;
    for (guint i = 0; installed && i < installed->len; ++i) {
        auto ref = FLATPAK_REF(g_ptr_array_index(installed, i));
        if (flatpak_ref_get_kind(ref) != FLATPAK_REF_KIND_APP) continue;
        g_autofree char *formatted = flatpak_ref_format_ref(ref);
        deployments.append(Sources::text(formatted) + ':' + Sources::text(flatpak_ref_get_commit(ref)));
    }
    deployments.sort(); inputs.append(QJsonArray::fromStringList(deployments));
    return true;
}
inline QString fingerprint() {
    QJsonArray inputs;
    // An upgrade invalidates parsed data even when the public beta is unchanged.
    inputs.append(stamp(QCoreApplication::applicationFilePath()));
    const auto exclusions = qEnvironmentVariableIsSet("FLUFF_APP_CENTER_EXCLUSIONS")
        ? qEnvironmentVariable("FLUFF_APP_CENTER_EXCLUSIONS") : QStringLiteral("/etc/flufflinux-appcenter/exclusions.conf");
    inputs.append(QJsonArray{exclusions, contents(exclusions)});
    QSettings settings(Sources::configPath(), QSettings::IniFormat);
    auto suppressed = settings.value("Sources/removedSystemSources").toStringList();
    suppressed.sort(); inputs.append(QJsonArray::fromStringList(suppressed));
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    if (!user) return {}; // No trustworthy input snapshot: use the normal worker.
    if (!installation(inputs, user)) return {};
    g_autoptr(GError) error = nullptr;
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, &error);
    if (error) return {};
    for (guint i = 0; systems && i < systems->len; ++i)
        if (!installation(inputs, FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)))) return {};
    return Sources::token(QString::fromUtf8(QJsonDocument(inputs).toJson(QJsonDocument::Compact)));
}
}
