#include <flatpak.h>
#include "flatpak_sizes.h"
#include "download_size.h"
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QLocale>
#include <QProcess>
#include <QSet>

namespace {
QString text(const char *value) { return QString::fromUtf8(value ? value : ""); }
QString setting(GKeyFile *key, const QByteArray &group, const char *name) {
    g_autofree char *value = g_key_file_get_string(key, group.constData(), name, nullptr);
    return text(value);
}
struct Source {
    QString name, url;
    QHash<QString, FlatpakRemoteRef *> refs;
    GPtrArray *owned = nullptr;
};

struct Lookup {
    QList<Source> sources;
    QSet<QString> installed, installedUser, visited;
    QStringList glDrivers;
    QString gtkTheme;
    bool driversRead = false, complete = true;
    quint64 total = 0;
    ~Lookup() { for (const auto &source : sources) if (source.owned) g_ptr_array_unref(source.owned); }

    void load(FlatpakInstallation *installation, bool user) {
        g_autoptr(GPtrArray) apps = flatpak_installation_list_installed_refs(installation, nullptr, nullptr);
        for (guint i = 0; apps && i < apps->len; ++i) {
            g_autofree char *ref = flatpak_ref_format_ref(FLATPAK_REF(g_ptr_array_index(apps, i)));
            installed.insert(text(ref));
            if (user) installedUser.insert(text(ref).section('/', 0, 2));
        }
        g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(installation, nullptr, nullptr);
        for (guint i = 0; remotes && i < remotes->len; ++i) {
            auto remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
            if (flatpak_remote_get_disabled(remote)) continue;
            const auto name = text(flatpak_remote_get_name(remote));
            g_autofree char *url = flatpak_remote_get_url(remote);
            // Never substitute a same-named system source for a different
            // user source. A matching URL can supply its existing metadata.
            bool duplicate = false;
            for (const auto &source : sources)
                if (source.name == name && (source.url != text(url) || !source.refs.isEmpty())) duplicate = true;
            if (duplicate) continue;
            auto refs = flatpak_installation_list_remote_refs_sync_full(installation, name.toUtf8(),
                FLATPAK_QUERY_FLAGS_ONLY_CACHED, nullptr, nullptr);
            Source source{name, text(url), {}, refs};
            for (guint j = 0; refs && j < refs->len; ++j) {
                auto ref = FLATPAK_REMOTE_REF(g_ptr_array_index(refs, j));
                g_autofree char *formatted = flatpak_ref_format_ref(FLATPAK_REF(ref));
                source.refs.insert(text(formatted), ref);
            }
            sources.append(source);
        }
    }
    bool matches(const QString &id, const QString &reasons, bool fallback) {
        if (reasons.isEmpty()) return fallback;
        const auto suffix = id.section('.', -1);
        for (const auto &reason : reasons.split(';', Qt::SkipEmptyParts)) {
            if (reason == "active-gl-driver") {
                if (!driversRead) {
                    driversRead = true;
                    QProcess drivers;
                    drivers.start("flatpak", {"--gl-drivers"});
                    if (drivers.waitForFinished(1000) && drivers.exitCode() == 0)
                        glDrivers = QString::fromUtf8(drivers.readAllStandardOutput()).simplified().split(' ');
                    else { drivers.kill(); drivers.waitForFinished(); complete = false; }
                }
                if (glDrivers.contains(suffix)) return true;
            } else if (reason == "active-gtk-theme") {
                if (gtkTheme == suffix) return true;
            } else if (reason == "have-intel-gpu") {
                if (QFileInfo::exists("/sys/module/i915") || QFileInfo::exists("/sys/module/xe")) return true;
            } else if (reason.startsWith("have-kernel-module-")) {
                const auto module = reason.mid(19);
                if (!module.contains('/') && QFileInfo::exists("/sys/module/" + module)) return true;
            } else if (reason.startsWith("on-xdg-desktop-")) {
                if (QString::fromUtf8(qgetenv("XDG_CURRENT_DESKTOP")).split(':').contains(reason.mid(15), Qt::CaseInsensitive)) return true;
            } else complete = false; // Do not guess for future selection rules.
        }
        return false;
    }
    void add(const QString &ref, int sourceIndex, bool app = false) {
        if ((!app && installed.contains(ref)) || visited.contains(ref)) return;
        visited.insert(ref);
        if (visited.size() > 256) { complete = false; return; }
        auto remoteRef = sources[sourceIndex].refs.value(ref, nullptr);
        if (!remoteRef) { complete = false; return; }
        const auto metadata = flatpak_remote_ref_get_metadata(remoteRef);
        if (!metadata) { complete = false; return; }
        total += flatpak_remote_ref_get_download_size(remoteRef);
        g_autoptr(GKeyFile) key = g_key_file_new();
        if (!g_key_file_load_from_data(key, static_cast<const char *>(g_bytes_get_data(metadata, nullptr)),
                g_bytes_get_size(metadata), G_KEY_FILE_NONE, nullptr)) { complete = false; return; }
        if (app) {
            const auto runtime = setting(key, "Application", "runtime");
            if (!runtime.isEmpty() && !installed.contains("runtime/" + runtime)) {
                int runtimeSource = sourceIndex;
                if (!sources[runtimeSource].refs.contains("runtime/" + runtime)) {
                    runtimeSource = -1;
                    for (int i = 0; i < sources.size(); ++i)
                        if (sources[i].refs.contains("runtime/" + runtime)) { runtimeSource = i; break; }
                }
                if (runtimeSource < 0) complete = false;
                else add("runtime/" + runtime, runtimeSource);
            }
        }
        g_auto(GStrv) groups = g_key_file_get_groups(key, nullptr);
        for (int i = 0; groups[i]; ++i) {
            const QByteArray group(groups[i]);
            if (!group.startsWith("Extension ")) continue;
            const auto extension = QString::fromUtf8(group.mid(10)).section('@', 0, 0);
            if (extension.endsWith(".Debug")) continue;
            auto versions = setting(key, group, "versions").split(';', Qt::SkipEmptyParts);
            if (versions.isEmpty()) {
                auto version = setting(key, group, "version");
                versions.append(version.isEmpty() ? ref.section('/', 3, 3) : version);
            }
            const bool subdirs = g_key_file_get_boolean(key, group, "subdirectories", nullptr);
            const bool autoDownload = !g_key_file_get_boolean(key, group, "no-autodownload", nullptr);
            const auto reasons = setting(key, group, "download-if");
            for (const auto &version : versions) {
                const auto tail = "/" + ref.section('/', 2, 2) + "/" + version;
                const auto exact = "runtime/" + extension + tail;
                QStringList candidates;
                if (sources[sourceIndex].refs.contains(exact)) candidates.append(exact);
                else if (subdirs) {
                    for (auto it = sources[sourceIndex].refs.cbegin(); it != sources[sourceIndex].refs.cend(); ++it) {
                        const auto id = it.key().section('/', 1, 1);
                        if (it.key().startsWith("runtime/" + extension + ".") && it.key().endsWith(tail)
                            && !id.mid(extension.size() + 1).contains('.')) candidates.append(it.key());
                    }
                }
                for (const auto &candidate : candidates) {
                    if (installed.contains(candidate)) continue;
                    if (installedUser.contains(candidate.section('/', 0, 2))
                        || matches(candidate.section('/', 1, 1), reasons, autoDownload)) add(candidate, sourceIndex);
                }
            }
        }
    }
};
}

QString localInstalledFlatpakSize(const QVariantMap &app, quint64 *bytes) {
    if (bytes) *bytes = 0;
    const auto scope = app.value("installation").toString();
    auto id = app.value("id").toString();
    if (id.endsWith(".desktop")) id.chop(8);
    const auto arch = app.value("installedArch").toString();
    const auto branch = app.value("installedBranch").toString();
    if (scope.isEmpty() || id.isEmpty() || arch.isEmpty() || branch.isEmpty()) return {};
    g_autoptr(FlatpakInstallation) installation = scope == "user"
        ? flatpak_installation_new_user(nullptr, nullptr)
        : scope == "system" ? flatpak_installation_new_system(nullptr, nullptr)
        : flatpak_installation_new_system_with_id(scope.toUtf8(), nullptr, nullptr);
    if (!installation) return {};
    g_autoptr(FlatpakInstalledRef) ref = flatpak_installation_get_installed_ref(installation,
        FLATPAK_REF_KIND_APP, id.toUtf8(), arch.toUtf8(), branch.toUtf8(), nullptr, nullptr);
    if (!ref) return {};
    const auto installedBytes = flatpak_installed_ref_get_installed_size(ref);
    if (bytes) *bytes = installedBytes;
    return downloadSizeText(installedBytes);
}

QVariantMap localFlatpakSizes(const QVariantMap &request) {
    Lookup lookup;
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    if (user) lookup.load(user, true);
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, nullptr);
    for (guint i = 0; systems && i < systems->len; ++i) lookup.load(FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)), false);
    auto schemaSource = g_settings_schema_source_get_default();
    g_autoptr(GSettingsSchema) schema = schemaSource ? g_settings_schema_source_lookup(schemaSource, "org.gnome.desktop.interface", true) : nullptr;
    if (schema) {
        g_autoptr(GSettings) settings = g_settings_new_full(schema, nullptr, nullptr);
        g_autofree char *theme = g_settings_get_string(settings, "gtk-theme");
        lookup.gtkTheme = text(theme);
    }
    auto remote = request.value("remote").toString();
    if (remote.isEmpty()) remote = "flathub";
    auto ref = request.value("flatpakRef").toString();
    if (ref.isEmpty()) ref = "app/" + request.value("id").toString() + "/" + text(flatpak_get_default_arch()) + "/stable";
    for (int i = 0; i < lookup.sources.size(); ++i) {
        if (lookup.sources[i].name != remote || !lookup.sources[i].refs.contains(ref)
            || (!request.value("sourceUrl").toString().isEmpty() && lookup.sources[i].url != request.value("sourceUrl"))) continue;
        auto app = lookup.sources[i].refs[ref];
        // A missing size/metadata is unknown, not a zero-byte download.
        if (!flatpak_remote_ref_get_metadata(app)) break;
        lookup.add(ref, i, true);
        const auto appBytes = flatpak_remote_ref_get_download_size(app);
        QVariantMap result{{"state", lookup.complete ? "ready" : "partial"}, {"appBytes", double(appBytes)},
            {"appSize", downloadSizeText(appBytes)}};
        if (lookup.complete) {
            result["totalBytes"] = double(lookup.total);
            result["totalSize"] = downloadSizeText(lookup.total);
        }
        return result;
    }
    return {{"state", "unavailable"}};
}
