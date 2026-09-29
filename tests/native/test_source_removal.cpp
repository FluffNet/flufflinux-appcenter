// Test-only helper core, confined to temporary installations. Production still
// requires Polkit/root and ignores installation-path environment overrides.
#include "../../src/source_removal.h"
#include <QCoreApplication>
#include <cassert>
#include <cstdio>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) return 99;
    const auto root = qEnvironmentVariable("APPCENTER_REMOVAL_FIXTURE");
    if (!root.startsWith("/tmp/appcenter-remove-used-") || !QFileInfo(root).isDir()) return 99;
    for (const auto *variable : {"FLATPAK_USER_DIR", "FLATPAK_SYSTEM_DIR", "FLATPAK_CONFIG_DIR"})
        if (!qEnvironmentVariable(variable).startsWith(root + "/")) return 99;
    const QString scope = QString::fromUtf8(argv[1]);
    QJsonArray members;
    for (const auto &value : Sources::list()) {
        const auto source = value.toObject();
        if (source["name"] == "fixture" && (scope == "merged" || source["scope"] == scope)) members.append(source);
    }
    assert(members.size() == (scope == "merged" ? 3 : 1));
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    std::vector<SourceRemoval::Target> targets;
    QString problem;
    assert(SourceRemoval::resolve(user, members, scope != "user" && scope != "merged", targets, problem));
    for (const auto &target : targets) {
        // Prove the regression fixture really is in use, not an empty remote.
        g_autoptr(GError) error = nullptr;
        assert(!flatpak_installation_remove_remote(target.installation.get(), "fixture", nullptr, &error));
        assert(g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_REMOTE_USED));
        auto stale = target; stale.expected["sourceKey"] = "stale";
        assert(!SourceRemoval::remove(stale, nullptr, problem));
        g_autoptr(GCancellable) cancelled = g_cancellable_new();
        g_cancellable_cancel(cancelled);
        assert(!SourceRemoval::remove(target, cancelled, problem));
        assert(SourceRemoval::matches(target.installation.get(), target.expected, problem));
        if (!SourceRemoval::remove(target, nullptr, problem)) qFatal("Removal failed: %s", qPrintable(problem));
        assert(!SourceRemoval::matches(target.installation.get(), target.expected, problem));
    }
    puts("PASS: in-use source removed; stale identity and pre-cancellation rejected");
}
