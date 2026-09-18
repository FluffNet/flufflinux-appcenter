#pragma once
#include <flatpak.h>
#include <ostree.h>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonDocument>
#include <QSet>
#include <QSettings>
#include <QUrl>

namespace Sources {
inline QString text(const char *s) { return QString::fromUtf8(s ? s : ""); }
inline QString configPath() {
#ifdef APPCENTER_SOURCE_TEST_CONFIG
    return APPCENTER_SOURCE_TEST_CONFIG;
#else
    return QDir::homePath() + "/.config/flufflinux-appcenter.conf";
#endif
}
inline QString url(FlatpakRemote *remote) {
    g_autofree char *value = flatpak_remote_get_url(remote);
    return text(value);
}
inline QString scope(FlatpakInstallation *installation) {
    return flatpak_installation_get_is_user(installation) ? "user"
        : text(flatpak_installation_get_id(installation));
}
inline QString identity(FlatpakInstallation *installation, FlatpakRemote *remote) {
    return scope(installation) + ":" + text(flatpak_remote_get_name(remote)) + ":" + url(remote);
}
inline QString token(const QString &value) {
    return QString::fromLatin1(QCryptographicHash::hash(value.toUtf8(), QCryptographicHash::Sha256).toHex());
}
// A familiar name is not proof of trust. Reject credentials, ports, queries,
// look-alike hosts, and other paths even when a remote is called "flathub".
inline QString officialDefinition(const QString &value) {
    const QUrl u(value);
    if (!u.isValid() || u.scheme() != "https" || !u.userInfo().isEmpty()
        || u.port(-1) != -1 || u.hasQuery() || u.hasFragment()
        || (u.host() != "dl.flathub.org" && u.host() != "flathub.org")) return {};
    auto path = u.path();
    if (path.endsWith('/')) path.chop(1);
    if (path == "/repo") return "https://dl.flathub.org/repo/flathub.flatpakrepo";
    if (path == "/beta-repo") return "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    return {};
}
inline QString userName(FlatpakInstallation *user, FlatpakInstallation *system, FlatpakRemote *remote) {
    const auto name = text(flatpak_remote_get_name(remote));
    g_autoptr(FlatpakRemote) existing = flatpak_installation_get_remote_by_name(user, name.toUtf8(), nullptr, nullptr);
    if (!existing || url(existing) == url(remote)) return name;
    // Never overwrite a different user source that happens to share a name.
    return name + "-system-" + token(identity(system, remote)).left(10);
}
inline bool suppressed(FlatpakInstallation *system, FlatpakRemote *remote) {
    QSettings settings(configPath(), QSettings::IniFormat);
    return settings.value("Sources/removedSystemSources").toStringList().contains(token(identity(system, remote)));
}
// Repository identity is independent of local names, enabled state and visual
// metadata, but includes signing keys and every other configured policy option.
// In particular, two endpoints with different keys/filters must never merge.
inline QString sourceKey(FlatpakInstallation *installation, FlatpakRemote *remote) {
    g_autoptr(GFile) path = g_file_get_child(flatpak_installation_get_path(installation), "repo");
    g_autoptr(OstreeRepo) repo = ostree_repo_new(path);
    if (!ostree_repo_open(repo, nullptr, nullptr)) return {};
    g_autoptr(GKeyFile) config = ostree_repo_copy_config(repo);
    const auto group = QByteArray("remote \"") + flatpak_remote_get_name(remote) + '"';
    g_auto(GStrv) keys = g_key_file_get_keys(config, group, nullptr, nullptr);
    if (!keys) return {};
    const QSet<QByteArray> localOptions{"xa.title", "xa.comment", "xa.description", "xa.homepage", "xa.icon",
        "xa.disable", "xa.prio", "xa.fluff-system-source", "gpgkeypath"};
    QJsonObject options;
    for (int i = 0; keys[i]; ++i) {
        if (localOptions.contains(keys[i])) continue;
        g_autofree char *value = g_key_file_get_string(config, group, keys[i], nullptr);
        options[text(keys[i])] = text(value);
    }
    g_autoptr(GPtrArray) trustedKeys = nullptr;
    if (!ostree_repo_remote_get_gpg_keys(repo, flatpak_remote_get_name(remote), nullptr, &trustedKeys, nullptr, nullptr)) return {};
    QStringList signatures;
    for (guint i = 0; i < trustedKeys->len; ++i) {
        g_autofree char *key = g_variant_print(static_cast<GVariant *>(g_ptr_array_index(trustedKeys, i)), true);
        signatures.append(text(key));
    }
    signatures.sort();
    options["signing-keys"] = QJsonArray::fromStringList(signatures);
    // A filter's contents, not merely its path, determine the available apps.
    const auto filterPath = options.value("xa.filter").toString();
    if (!filterPath.isEmpty()) {
        QFile filter(filterPath);
        if (!filter.open(QIODevice::ReadOnly)) return {};
        options["xa.filter"] = QString::fromLatin1(QCryptographicHash::hash(filter.readAll(), QCryptographicHash::Sha256).toHex());
    }
    return token(QString::fromUtf8(QJsonDocument(options).toJson(QJsonDocument::Compact)));
}
inline QJsonArray group(const QJsonArray &sources) {
    QJsonArray result;
    for (const auto &entry : sources) {
        const auto source = entry.toObject();
        int match = -1;
        for (int i = 0; i < result.size(); ++i) {
            const auto candidate = result[i].toObject();
            if (source["sourceKey"].toString().isEmpty() || candidate["sourceKey"] != source["sourceKey"]) continue;
            bool sameScope = false;
            for (const auto &member : candidate["members"].toArray())
                sameScope |= member.toObject()["scope"] == source["scope"];
            if (!sameScope) { match = i; break; }
        }
        auto row = match < 0 ? source : result[match].toObject();
        auto members = row["members"].toArray(); members.append(source); row["members"] = members;
        const bool user = source["scope"] == "user";
        row["hasUser"] = row["hasUser"].toBool() || user;
        row["hasSystem"] = row["hasSystem"].toBool() || !user;
        if (row["hasUser"].toBool() && row["hasSystem"].toBool()) row["scope"] = "merged";
        if (user) row["enabled"] = source["enabled"]; // The toggle governs the user's copy.
        QStringList identities;
        for (const auto &member : members) {
            const auto m = member.toObject();
            identities.append(m["scope"].toString() + ":" + m["name"].toString() + ":" + m["url"].toString() + ":" + m["sourceKey"].toString());
        }
        identities.sort(); row["id"] = token(identities.join('\n'));
        if (match < 0) result.append(row); else result[match] = row;
    }
    return result;
}
inline QJsonArray list() {
    QJsonArray result;
    auto append = [&](FlatpakInstallation *installation) {
        g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(installation, nullptr, nullptr);
        for (guint i = 0; remotes && i < remotes->len; ++i) {
            auto remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
            if (flatpak_remote_get_remote_type(remote) != FLATPAK_REMOTE_TYPE_STATIC) continue;
            g_autofree char *title = flatpak_remote_get_title(remote);
            result.append(QJsonObject{{"name", text(flatpak_remote_get_name(remote))},
                {"title", text(title)}, {"url", url(remote)}, {"scope", scope(installation)},
                {"enabled", !flatpak_remote_get_disabled(remote)},
                {"sourceKey", sourceKey(installation, remote)},
                {"verified", bool(flatpak_remote_get_gpg_verify(remote))}});
        }
    };
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    if (user) append(user);
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, nullptr);
    for (guint i = 0; systems && i < systems->len; ++i) append(FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)));
    return result;
}
// Clone the entire system remote configuration, including filters, collection
// IDs, authenticators and verification policy. Only public signing keys are
// imported. System files and existing user sources are never modified.
inline bool mirror(FlatpakInstallation *user, FlatpakInstallation *system, FlatpakRemote *remote,
                   GCancellable *cancel, QString &problem) {
    const auto name = userName(user, system, remote);
    g_autoptr(FlatpakRemote) existing = flatpak_installation_get_remote_by_name(user, name.toUtf8(), cancel, nullptr);
    if (existing) {
        if (url(existing) == url(remote)) return true;
        problem = "The user source " + name + " has a different address. It has not been changed.";
        return false;
    }
    g_autoptr(GError) error = nullptr;
    g_autoptr(GFile) systemPath = g_file_get_child(flatpak_installation_get_path(system), "repo");
    g_autoptr(GFile) userPath = g_file_get_child(flatpak_installation_get_path(user), "repo");
    g_autoptr(OstreeRepo) sourceRepo = ostree_repo_new(systemPath);
    g_autoptr(OstreeRepo) targetRepo = ostree_repo_new(userPath);
    if (!ostree_repo_open(sourceRepo, cancel, &error) || !ostree_repo_open(targetRepo, cancel, &error)) {
        problem = text(error->message); return false;
    }
    g_autoptr(GKeyFile) config = ostree_repo_copy_config(sourceRepo);
    const auto group = QByteArray("remote \"") + flatpak_remote_get_name(remote) + '"';
    g_auto(GStrv) keys = g_key_file_get_keys(config, group, nullptr, &error);
    if (!keys) { problem = text(error->message); return false; }
    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
    for (int i = 0; keys[i]; ++i) {
        if (QByteArray(keys[i]) == "xa.disable") continue;
        g_autofree char *value = g_key_file_get_string(config, group, keys[i], nullptr);
        g_variant_builder_add(&options, "{sv}", keys[i], g_variant_new_string(value ? value : ""));
    }
    // Do not expose a usable source before its key import has succeeded.
    g_variant_builder_add(&options, "{sv}", "xa.disable", g_variant_new_boolean(true));
    g_variant_builder_add(&options, "{sv}", "xa.fluff-system-source",
                          g_variant_new_string(token(identity(system, remote)).toUtf8()));
    g_autoptr(GVariant) values = g_variant_ref_sink(g_variant_builder_end(&options));
    g_autofree char *systemDirectory = g_file_get_path(systemPath);
    QFile keyring(QDir(text(systemDirectory)).filePath(text(flatpak_remote_get_name(remote)) + ".trustedkeys.gpg"));
    QByteArray signingKeys;
    if (keyring.open(QIODevice::ReadOnly)) signingKeys = keyring.readAll();
    g_autofree char *keyPath = g_key_file_get_string(config, group, "gpgkeypath", nullptr);
    const bool verify = flatpak_remote_get_gpg_verify(remote)
        || g_key_file_get_boolean(config, group, "gpg-verify-summary", nullptr);
    if (verify && signingKeys.isEmpty() && (!keyPath || !*keyPath)) {
        problem = "Cannot copy the signing keys for " + name + ". Verification has not been disabled.";
        return false;
    }
    if (!ostree_repo_remote_add(targetRepo, name.toUtf8(), url(remote).toUtf8(), values, cancel, &error)) {
        problem = text(error->message); return false;
    }
    if (!signingKeys.isEmpty()) {
        g_autoptr(GInputStream) stream = g_memory_input_stream_new_from_data(signingKeys.constData(), signingKeys.size(), nullptr);
        if (!ostree_repo_remote_gpg_import(targetRepo, name.toUtf8(), stream, nullptr, nullptr, cancel, &error)) {
            problem = text(error->message);
            ostree_repo_remote_delete(targetRepo, name.toUtf8(), nullptr, nullptr);
            flatpak_installation_drop_caches(user, nullptr, nullptr);
            return false;
        }
    }
    flatpak_installation_drop_caches(user, cancel, nullptr);
    g_autoptr(FlatpakRemote) copy = flatpak_installation_get_remote_by_name(user, name.toUtf8(), cancel, &error);
    if (!copy) { problem = text(error->message); return false; }
    flatpak_remote_set_disabled(copy, flatpak_remote_get_disabled(remote));
    if (!flatpak_installation_modify_remote(user, copy, cancel, &error)) { problem = text(error->message); return false; }
    return true;
}
inline void rememberRemoval(FlatpakInstallation *user, FlatpakRemote *remote) {
    QSettings settings(configPath(), QSettings::IniFormat);
    auto removed = settings.value("Sources/removedSystemSources").toStringList();
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, nullptr);
    for (guint i = 0; systems && i < systems->len; ++i) {
        auto system = FLATPAK_INSTALLATION(g_ptr_array_index(systems, i));
        g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(system, nullptr, nullptr);
        for (guint j = 0; remotes && j < remotes->len; ++j) {
            auto source = FLATPAK_REMOTE(g_ptr_array_index(remotes, j));
            if (userName(user, system, source) == text(flatpak_remote_get_name(remote)) && url(source) == url(remote))
                removed.append(token(identity(system, source)));
        }
    }
    removed.removeDuplicates();
    settings.setValue("Sources/removedSystemSources", removed);
    settings.setValue("Sources/initialized", true);
}
} // namespace Sources
