#include "flatpak_sources.h"

extern "C" void fluff_visit_catalogs(void (*visit)(const char *, const char *, const char *, void *), void *data) {
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    if (!user) return;
    auto read = [&](FlatpakInstallation *installation, bool isUser) {
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
            g_autofree char *path = g_file_get_path(directory);
            visit(path, name.toUtf8(), Sources::url(remote).toUtf8(), data);
        }
    };
    read(user, true);
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, nullptr);
    for (guint i = 0; systems && i < systems->len; ++i) read(FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)), false);
}
