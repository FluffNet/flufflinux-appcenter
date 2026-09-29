#include <flatpak.h>
#include "flatpak_permissions.h"
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <iostream>
#include <unistd.h>

namespace {
QByteArray bytes(GBytes *value) {
    if (!value) return {};
    gsize size = 0;
    const auto data = static_cast<const char *>(g_bytes_get_data(value, &size));
    if (size > 1024 * 1024) return {};
    return QByteArray(data, qsizetype(size));
}
QVariantMap readPermissions(const QVariantMap &request) {
    const QUrl input(request.value("source").toString());
    const auto path = input.isLocalFile() ? input.toLocalFile() : input.scheme().isEmpty() ? input.toString() : QString();
    if (path.endsWith(".flatpak", Qt::CaseInsensitive) && QFileInfo(path).isFile()) {
        g_autoptr(GFile) file = g_file_new_for_path(path.toUtf8());
        g_autoptr(FlatpakBundleRef) bundle = flatpak_bundle_ref_new(file, nullptr);
        if (!bundle) return AppPermissions::error(AppPermissions::tr("Could not read this local Flatpak bundle."));
        return AppPermissions::parse(bytes(flatpak_bundle_ref_get_metadata(bundle)));
    }
    const auto remoteName = request.value("remote").toString();
    const auto remoteUrl = request.value("sourceUrl").toString();
    const auto fullRef = request.value("flatpakRef").toString();
    g_autoptr(FlatpakRef) ref = flatpak_ref_parse(fullRef.toUtf8(), nullptr);
    if (!ref || flatpak_ref_get_kind(ref) != FLATPAK_REF_KIND_APP || remoteName.isEmpty() || remoteUrl.isEmpty())
        return AppPermissions::error(AppPermissions::tr("Permission information is not available for this app source."));
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, nullptr);
    QList<FlatpakInstallation *> installations;
    if (user) installations.append(user);
    for (guint i = 0; systems && i < systems->len; ++i) installations.append(FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)));
    QList<FlatpakInstallation *> matching;
    for (auto installation : installations) {
        g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(installation, remoteName.toUtf8(), nullptr, nullptr);
        if (!remote) continue;
        g_autofree char *url = flatpak_remote_get_url(remote);
        // Never substitute another repository, branch or architecture.
        if (QString::fromUtf8(url ? url : "") != remoteUrl) continue;
        g_autoptr(FlatpakRemoteRef) cached = flatpak_installation_fetch_remote_ref_sync_full(installation, remoteName.toUtf8(),
            FLATPAK_REF_KIND_APP, flatpak_ref_get_name(ref), flatpak_ref_get_arch(ref), flatpak_ref_get_branch(ref),
            FLATPAK_QUERY_FLAGS_ONLY_CACHED, nullptr, nullptr);
        const auto metadata = cached ? bytes(flatpak_remote_ref_get_metadata(cached)) : QByteArray();
        if (!metadata.isEmpty()) return AppPermissions::parse(metadata);
        if (!flatpak_remote_get_disabled(remote)) matching.append(installation);
    }
    // Metadata-only fallback runs outside the GUI; it cannot install an app,
    // add a repository, trigger authorization or create a Queue entry.
    for (auto installation : matching) {
        g_autoptr(GBytes) metadata = flatpak_installation_fetch_remote_metadata_sync(installation, remoteName.toUtf8(), ref, nullptr, nullptr);
        const auto data = bytes(metadata);
        if (!data.isEmpty()) return AppPermissions::parse(data);
    }
    return AppPermissions::error(AppPermissions::tr("Could not read permissions from the selected source. Check your connection and try again."));
}
}

extern "C" int fluff_permissions_worker(const char *json) {
    int argc = 1;
    char name[] = "flufflinux-appcenter-permissions";
    char *argv[] = {name, nullptr};
    QCoreApplication app(argc, argv);
    const auto result = geteuid() == 0 ? AppPermissions::error(AppPermissions::tr("Run App Center as your desktop user."))
        : readPermissions(QJsonDocument::fromJson(QByteArray(json)).object().toVariantMap());
    std::cout << QJsonDocument::fromVariant(result).toJson(QJsonDocument::Compact).constData() << std::endl;
    return 0;
}
