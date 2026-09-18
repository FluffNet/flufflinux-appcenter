#pragma once
#include <glib.h>
#include <QCoreApplication>
#include <QMap>
#include <QSet>
#include <QVariant>

namespace AppPermissions {
inline QString tr(const char *s) { return QCoreApplication::translate("AppPermissions", s); }
inline QVariantMap error(const QString &message) { return {{"state", "error"}, {"message", message}}; }
inline QVariantMap parse(const QByteArray &data, bool installed = false) {
    if (data.size() > 1024 * 1024) return error(tr("The permission information is too large to display."));
    if (data.contains('\0')) return error(tr("Flatpak returned invalid permission information."));
    g_autoptr(GKeyFile) key = g_key_file_new();
    g_autoptr(GError) problem = nullptr;
    if (!data.trimmed().isEmpty() && !g_key_file_load_from_data(key, data.constData(), data.size(), G_KEY_FILE_NONE, &problem))
        return error(tr("Flatpak returned invalid permission information."));
    if (!installed && !g_key_file_has_group(key, "Application"))
        return error(tr("The source did not provide application permission information."));
    bool invalidList = false;
    auto list = [&](const char *group, const char *name) {
        QStringList values;
        if (!g_key_file_has_key(key, group, name, nullptr)) return values;
        g_autoptr(GError) listError = nullptr;
        g_auto(GStrv) items = g_key_file_get_string_list(key, group, name, nullptr, &listError);
        if (listError) invalidList = true;
        for (int i = 0; items && items[i]; ++i) values.append(QString::fromUtf8(items[i]));
        values.removeAll(QString()); values.removeDuplicates(); values.sort(Qt::CaseInsensitive);
        return values;
    };
    const auto shared = list("Context", "shared"), sockets = list("Context", "sockets");
    QVariantList groups;
    auto add = [&](const QString &id, const QString &title, const QString &icon, const QString &description, QStringList details) {
        if (details.isEmpty()) return;
        details.removeDuplicates(); details.sort(Qt::CaseInsensitive);
        groups.append(QVariantMap{{"id", id}, {"title", title}, {"icon", icon}, {"description", description}, {"details", details}});
    };
    auto labeled = [&](const QStringList &values, const QMap<QString, QString> &labels) {
        QStringList result;
        for (auto value : values) {
            const bool denied = value.startsWith('!');
            if (denied) value.remove(0, 1);
            auto label = labels.value(value, value);
            result.append(denied ? tr("%1 — denied").arg(label) : label);
        }
        return result;
    };
    QStringList network, ipc, audio, display, otherSockets, otherShared;
    for (const auto &value : shared) {
        const auto name = value.startsWith('!') ? value.mid(1) : value;
        if (name == "network") network.append(value);
        else if (name == "ipc") ipc.append(value);
        else otherShared.append(value);
    }
    for (const auto &value : sockets) {
        const auto name = value.startsWith('!') ? value.mid(1) : value;
        if (name == "pulseaudio") audio.append(value);
        else if (name == "x11" || name == "fallback-x11" || name == "wayland") display.append(value);
        else if (name != "session-bus" && name != "system-bus") otherSockets.append(value);
    }
    add("network", tr("Network Access"), "network-wireless", tr("Internet and local network connections."),
        labeled(network, {{"network", tr("Network connections")}}));
    add("audio", tr("Sound System Access"), "audio-volume-high", tr("Audio playback and recording through the sound server."),
        labeled(audio, {{"pulseaudio", tr("Play and record audio")}}));
    add("devices", tr("Device Access"), "computer", tr("Access to hardware devices outside the sandbox."),
        labeled(list("Context", "devices"), {{"all", tr("All devices")}, {"dri", tr("Graphics acceleration")},
            {"kvm", tr("Virtualization")}, {"shm", tr("Shared device memory")}, {"input", tr("Input devices")}, {"usb", tr("USB devices")}}));
    add("display", tr("Display Access"), "video-display", tr("Connections to the desktop display system."),
        labeled(display, {{"wayland", tr("Wayland")}, {"x11", tr("X11 — access to other X11 windows and input")},
            {"fallback-x11", tr("X11 when Wayland is unavailable")}}));
    add("ipc", tr("Shared Memory Access"), "preferences-system", tr("Inter-process communication shared with the host session."),
        labeled(ipc, {{"ipc", tr("Host IPC namespace")}}));
    QStringList files;
    for (auto path : list("Context", "filesystems")) {
        const bool denied = path.startsWith('!');
        if (denied) path.remove(0, 1);
        QString mode = denied ? tr("denied") : tr("read and write");
        if (path.endsWith(":ro")) { path.chop(3); if (!denied) mode = tr("read only"); }
        else if (path.endsWith(":rw")) path.chop(3);
        else if (path.endsWith(":create")) { path.chop(7); if (!denied) mode = tr("read, write and create"); }
        const QMap<QString, QString> names{{"host", tr("Host files")}, {"home", tr("Home folder")},
            {"host-os", tr("Operating system files")}, {"host-etc", tr("System configuration")},
            {"host-root", tr("Root filesystem")}, {"xdg-desktop", tr("Desktop")}, {"xdg-documents", tr("Documents")},
            {"xdg-download", tr("Downloads")}, {"xdg-music", tr("Music")}, {"xdg-pictures", tr("Pictures")},
            {"xdg-videos", tr("Videos")}, {"xdg-public-share", tr("Public folder")}, {"xdg-templates", tr("Templates")}};
        files.append(tr("%1 — %2").arg(names.value(path, path), mode));
    }
    add("files", tr("File Access"), "folder", tr("Locations available outside the app’s private storage. Denied entries are exceptions to broader access."), files);
    add("persistent", tr("Persistent Storage"), "document-save", tr("Sandbox home locations saved in this app’s private storage, not access to your real home folder."), labeled(list("Context", "persistent"), {}));
    auto bus = [&](const char *group, const QString &socket, const QString &id, const QString &title, const QString &description) {
        QStringList details;
        if (sockets.contains(socket)) details.append(tr("Unrestricted access to this bus"));
        if (sockets.contains("!" + socket)) details.append(tr("Unrestricted access denied; individual rules apply"));
        g_auto(GStrv) names = g_key_file_get_keys(key, group, nullptr, nullptr);
        for (int i = 0; names && names[i]; ++i) {
            g_autofree char *value = g_key_file_get_string(key, group, names[i], nullptr);
            const auto policy = QString::fromUtf8(value ? value : "");
            const QMap<QString, QString> modes{{"talk", tr("communicate")}, {"own", tr("own service name")}, {"see", tr("see service name")}, {"none", tr("denied")}};
            details.append(tr("%1 — %2").arg(QString::fromUtf8(names[i]), modes.value(policy, policy)));
        }
        add(id, title, "network-connect", description, details);
    };
    bus("Session Bus Policy", "session-bus", "session-bus", tr("Session Bus Access"), tr("Communication with applications and services in your desktop session."));
    bus("System Bus Policy", "system-bus", "system-bus", tr("System Bus Access"), tr("Communication with system-wide services."));
    add("features", tr("Additional Capabilities"), "preferences-system", tr("Extra capabilities enabled or denied by the sandbox configuration."),
        labeled(list("Context", "features"), {{"devel", tr("Development and debugging system calls")}, {"multiarch", tr("Programs for other processor architectures")},
            {"bluetooth", tr("Bluetooth sockets")}, {"canbus", tr("CAN bus sockets")}, {"per-app-dev-shm", tr("Shared memory between this app’s instances")}}));
    add("sockets", tr("Other Socket Access"), "network-connect", tr("Other host connections requested by the app."),
        labeled(otherSockets, {{"ssh-auth", tr("SSH authentication agent")}, {"gpg-agent", tr("GPG agent")}, {"pcsc", tr("Smart cards")}, {"cups", tr("Printing service")}, {"inherit-wayland-socket", tr("Inherited Wayland connection")}}));
    QStringList usb;
    for (const auto &value : list("USB Devices", "enumerable-devices")) usb.append(tr("%1 — visible to the USB portal").arg(value));
    for (const auto &value : list("USB Devices", "hidden-devices")) usb.append(tr("%1 — hidden from the USB portal").arg(value));
    add("usb", tr("USB Device Portal"), "drive-removable-media-usb", tr("Which USB devices can be listed through the portal. Device access still requires portal authorization."), usb);
    // Preserve unrecognized/future context and policy entries instead of
    // silently presenting an incomplete list as 'no permissions'. Never show
    // [Environment]: values are settings, not permissions, and may be secrets.
    QStringList other = otherShared;
    const QSet<QString> known{"shared", "sockets", "devices", "filesystems", "persistent", "features", "unset-environment"};
    g_auto(GStrv) keys = g_key_file_get_keys(key, "Context", nullptr, nullptr);
    for (int i = 0; keys && keys[i]; ++i) {
        if (known.contains(QString::fromUtf8(keys[i]))) continue;
        g_autofree char *value = g_key_file_get_value(key, "Context", keys[i], nullptr);
        other.append(QString::fromUtf8(keys[i]) + ": " + QString::fromUtf8(value ? value : ""));
    }
    g_auto(GStrv) sections = g_key_file_get_groups(key, nullptr);
    for (int i = 0; sections && sections[i]; ++i) {
        const auto section = QString::fromUtf8(sections[i]);
        if (!section.startsWith("Policy ")) continue;
        g_auto(GStrv) policyKeys = g_key_file_get_keys(key, sections[i], nullptr, nullptr);
        for (int j = 0; policyKeys && policyKeys[j]; ++j)
            for (const auto &value : list(sections[i], policyKeys[j]))
                other.append(section.mid(7) + " / " + QString::fromUtf8(policyKeys[j]) + ": " + value);
    }
    add("other", tr("Other Permissions and Conditions"), "dialog-information", tr("Additional rules reported by Flatpak."), other);
    if (invalidList) return error(tr("Flatpak returned invalid permission information."));
    return {{"state", "ready"}, {"groups", groups}};
}
}
