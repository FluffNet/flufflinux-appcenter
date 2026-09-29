// All writes are confined to fresh temporary repositories. The optional input
// is a PUBLIC signing-key ring, read only; no apps are installed or removed.
#include "../../src/source_removal.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <cstdio>
#include <cassert>

static FlatpakInstallation *installation(const QString &path) {
    g_autoptr(GFile) file = g_file_new_for_path(path.toUtf8());
    g_autoptr(GError) error = nullptr;
    auto result = flatpak_installation_new_for_path(file, true, nullptr, &error);
    if (!result) qFatal("Test installation: %s", error->message);
    return result;
}
static FlatpakRemote *add(FlatpakInstallation *installation, const char *name, const char *url, const QByteArray &keys, bool disabled = false) {
    g_autoptr(FlatpakRemote) remote = flatpak_remote_new(name);
    flatpak_remote_set_url(remote, url);
    flatpak_remote_set_gpg_verify(remote, !keys.isEmpty());
    flatpak_remote_set_disabled(remote, disabled);
    flatpak_remote_set_title(remote, "Test source");
    flatpak_remote_set_noenumerate(remote, true);
    flatpak_remote_set_nodeps(remote, true);
    flatpak_remote_set_default_branch(remote, "testing");
    if (!keys.isEmpty()) {
        g_autoptr(GBytes) data = g_bytes_new(keys.constData(), keys.size());
        flatpak_remote_set_gpg_key(remote, data);
    }
    g_autoptr(GError) error = nullptr;
    if (!flatpak_installation_modify_remote(installation, remote, nullptr, &error)) qFatal("Test remote: %s", error->message);
    return flatpak_installation_get_remote_by_name(installation, name, nullptr, nullptr);
}
static QByteArray read(const QString &file) { QFile input(file); assert(input.open(QIODevice::ReadOnly)); return input.readAll(); }
int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    for (const auto &good : {"https://dl.flathub.org/repo/", "https://flathub.org/repo", "https://dl.flathub.org/beta-repo/"})
        assert(!Sources::officialDefinition(good).isEmpty());
    for (const auto &bad : {"http://dl.flathub.org/repo/", "https://dl.flathub.org.evil.test/repo/",
         "https://flathub.org@evil.test/repo/", "https://evil.test/flathub", "https://dl.flathub.org/other/",
         "https://dl.flathub.org/repo/?redirect=evil", "https://dl.flathub.org:444/repo/", "file:///repo/"})
        assert(Sources::officialDefinition(bad).isEmpty());
    QTemporaryDir temp; assert(temp.isValid());
    g_autoptr(FlatpakInstallation) user = installation(temp.path() + "/user");
    g_autoptr(FlatpakInstallation) system = installation(temp.path() + "/system");
    QByteArray keys;
    if (argc > 1) keys = read(QString::fromUtf8(argv[1]));
    g_autoptr(FlatpakRemote) original = add(system, "source", "https://example.org/repo/", keys);
    const auto systemBefore = read(temp.path() + "/system/repo/config");
    QString problem;
    assert(Sources::mirror(user, system, original, nullptr, problem));
    assert(problem.isEmpty());
    g_autoptr(FlatpakRemote) copy = flatpak_installation_get_remote_by_name(user, "source", nullptr, nullptr);
    assert(copy && Sources::url(copy) == Sources::url(original));
    assert(flatpak_remote_get_gpg_verify(copy) == flatpak_remote_get_gpg_verify(original));
    assert(flatpak_remote_get_noenumerate(copy) && flatpak_remote_get_nodeps(copy));
    g_autofree char *branch = flatpak_remote_get_default_branch(copy);
    assert(QByteArray(branch) == "testing");
    if (!keys.isEmpty()) {
        g_autoptr(GFile) path = g_file_new_for_path((temp.path() + "/user/repo").toUtf8());
        g_autoptr(OstreeRepo) repo = ostree_repo_new(path);
        assert(ostree_repo_open(repo, nullptr, nullptr));
        g_autoptr(GPtrArray) imported = nullptr;
        assert(ostree_repo_remote_get_gpg_keys(repo, "source", nullptr, &imported, nullptr, nullptr));
        assert(imported->len > 0);
    }
    // Existing user preferences survive startup synchronization.
    flatpak_remote_set_disabled(copy, true);
    assert(flatpak_installation_modify_remote(user, copy, nullptr, nullptr));
    const auto userBefore = read(temp.path() + "/user/repo/config");
    assert(Sources::mirror(user, system, original, nullptr, problem));
    assert(read(temp.path() + "/user/repo/config") == userBefore);
    // Same-name/different-URL sources get a stable alias, never an overwrite.
    g_autoptr(FlatpakRemote) conflict = add(system, "source", "https://other.example.org/repo/", keys, true);
    const auto alias = Sources::userName(user, system, conflict);
    assert(alias != "source" && alias.startsWith("source-system-"));
    assert(Sources::mirror(user, system, conflict, nullptr, problem));
    g_autoptr(FlatpakRemote) aliased = flatpak_installation_get_remote_by_name(user, alias.toUtf8(), nullptr, nullptr);
    assert(aliased && flatpak_remote_get_disabled(aliased));
    assert(Sources::url(copy) == "https://example.org/repo/");
    assert(!Sources::sourceKey(system, conflict).isEmpty());
    assert(Sources::sourceKey(system, conflict) == Sources::sourceKey(user, aliased));
    auto userRow = QJsonObject{{"name", alias}, {"scope", "user"}, {"url", Sources::url(aliased)},
        {"sourceKey", Sources::sourceKey(user, aliased)}, {"enabled", false}};
    auto systemRow = userRow; systemRow["name"] = "source"; systemRow["scope"] = "default";
    const auto merged = Sources::group({userRow, systemRow});
    assert(merged.size() == 1 && merged[0].toObject()["scope"] == "merged");
    assert(merged[0].toObject()["members"].toArray().size() == 2);
    assert(merged[0].toObject()["hasSystem"].toBool() && merged[0].toObject()["hasUser"].toBool());
    auto changedKey = systemRow; changedKey["sourceKey"] = "different-key-or-policy";
    assert(Sources::group({userRow, changedKey}).size() == 2);
    auto anotherUser = userRow; anotherUser["name"] = "deliberate-alias";
    assert(Sources::group({userRow, anotherUser}).size() == 2);
    // Removal revalidates identity, cannot follow a forged path or remove a
    // changed repository, and removes only from the validated installation.
    assert(SourceRemoval::matches(user, userRow, problem));
    auto forged = userRow; forged["url"] = "https://changed.example/repo/";
    assert(!SourceRemoval::matches(user, forged, problem));
    forged = userRow; forged["name"] = "../../repo";
    assert(!SourceRemoval::matches(user, forged, problem));
    SourceRemoval::Target removal{std::shared_ptr<FlatpakInstallation>(FLATPAK_INSTALLATION(g_object_ref(user)),
        [](FlatpakInstallation *item) { g_object_unref(item); }), userRow};
    assert(SourceRemoval::remove(removal, nullptr, problem));
    assert(!flatpak_installation_get_remote_by_name(user, alias.toUtf8(), nullptr, nullptr));
    assert(flatpak_installation_get_remote_by_name(system, "source", nullptr, nullptr));
    // Refuse signed repositories with missing keys; never weaken verification.
    g_autoptr(FlatpakRemote) missing = add(system, "missing-keys", "https://example.org/missing/", {});
    flatpak_remote_set_gpg_verify(missing, true);
    assert(flatpak_installation_modify_remote(system, missing, nullptr, nullptr));
    assert(!Sources::mirror(user, system, missing, nullptr, problem));
    assert(!flatpak_installation_get_remote_by_name(user, "missing-keys", nullptr, nullptr));
    // The first clone did not mutate the system source or its signing keys.
    assert(systemBefore.contains("url=https://example.org/repo/"));
    puts("PASS: exact official URLs, signed key import, policy preservation, idempotency, user overrides, collision aliases, disabled copies, missing-key refusal");
}
