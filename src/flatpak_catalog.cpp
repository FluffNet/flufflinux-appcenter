#include "flatpak_sources.h"
#include <QHash>
#include <QSet>

namespace {
QHash<QString, quint64> downloadSizes;
QSet<QString> installedIds;
QString sizeKey(const QString &remote, const QString &url, const QString &ref) {
    return remote + '\n' + url + '\n' + ref;
}

}

extern "C" bool fluff_catalog_app_installed(const char *id) {
    return installedIds.contains(QString::fromUtf8(id));
}
extern "C" double fluff_catalog_download_size(const char *remote, const char *url, const char *ref) {
    const auto key = sizeKey(QString::fromUtf8(remote), QString::fromUtf8(url), QString::fromUtf8(ref));
    const auto found = downloadSizes.constFind(key);
    return found == downloadSizes.cend() ? -1 : double(found.value());
}

extern "C" void fluff_visit_catalogs(void (*visit)(const char *, const char *, const char *, void *), void *data) {
    downloadSizes.clear();
    installedIds.clear();
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    if (!user) return;
    auto read = [&](FlatpakInstallation *installation, bool isUser) {
        g_autoptr(GPtrArray) installed = flatpak_installation_list_installed_refs(installation, nullptr, nullptr);
        for (guint i = 0; installed && i < installed->len; ++i) {
            auto ref = FLATPAK_REF(g_ptr_array_index(installed, i));
            if (flatpak_ref_get_kind(ref) == FLATPAK_REF_KIND_APP) {
                auto id = QString::fromUtf8(flatpak_ref_get_name(ref));
                if (id.endsWith(".desktop")) id.chop(8);
                installedIds.insert(id);
            }
        }
        g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(installation, nullptr, nullptr);
        for (guint i = 0; remotes && i < remotes->len; ++i) {
            auto remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
            if (flatpak_remote_get_disabled(remote) || flatpak_remote_get_noenumerate(remote)) continue;
            auto name = Sources::text(flatpak_remote_get_name(remote));
            if (!isUser) {
                if (Sources::suppressed(installation, remote)) continue;
                name = Sources::userName(user, installation, remote);
                g_autoptr(FlatpakRemote) copy = flatpak_installation_get_remote_by_name(user, name.toUtf8(), nullptr, nullptr);
                if (copy && (flatpak_remote_get_disabled(copy) || Sources::url(copy) != Sources::url(remote))) continue;
            }
            g_autoptr(GFile) directory = flatpak_remote_get_appstream_dir(remote, nullptr);
            if (!directory) continue;
            // One cached lookup per source, never thousands of per-app network
            // queries or an implicit update check just for catalog sorting.
            g_autoptr(GPtrArray) refs = flatpak_installation_list_remote_refs_sync_full(installation,
                flatpak_remote_get_name(remote), FLATPAK_QUERY_FLAGS_ONLY_CACHED, nullptr, nullptr);
            for (guint j = 0; refs && j < refs->len; ++j) {
                auto ref = FLATPAK_REMOTE_REF(g_ptr_array_index(refs, j));
                if (flatpak_ref_get_kind(FLATPAK_REF(ref)) != FLATPAK_REF_KIND_APP
                    || !flatpak_remote_ref_get_metadata(ref)) continue;
                g_autofree char *formatted = flatpak_ref_format_ref(FLATPAK_REF(ref));
                const auto key = sizeKey(name, Sources::url(remote), QString::fromUtf8(formatted));
                if (!downloadSizes.contains(key)) downloadSizes.insert(key, flatpak_remote_ref_get_download_size(ref));
            }
            g_autofree char *path = g_file_get_path(directory);
            visit(path, name.toUtf8(), Sources::url(remote).toUtf8(), data);
        }
    };
    read(user, true);
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, nullptr);
    for (guint i = 0; systems && i < systems->len; ++i) read(FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)), false);
}
