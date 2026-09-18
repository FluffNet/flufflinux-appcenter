// The only privileged entry point. It cannot install apps, execute arbitrary
// commands, select filesystem paths, or change signing/authorization policy.
#include "source_removal.h"
#include <QCoreApplication>
#include <cstdio>
#include <unistd.h>

int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    if (geteuid() != 0 || argc != 2 || QByteArray(argv[1]).size() > 65536) {
        std::fputs("Administrator authorization and a bounded source-removal request are required.\n", stderr); return 1;
    }
    // pkexec supplies a sanitized environment; never accept installation-path
    // overrides even if an administrator invokes this helper by another route.
    for (const auto *name : {"FLATPAK_USER_DIR", "FLATPAK_SYSTEM_DIR", "FLATPAK_CONFIG_DIR"}) qunsetenv(name);
    const auto document = QJsonDocument::fromJson(argv[1]);
    std::vector<SourceRemoval::Target> targets;
    QString problem;
    if (!document.isArray() || !SourceRemoval::resolve(nullptr, document.array(), true, targets, problem)) {
        std::fprintf(stderr, "%s\n", qPrintable(problem.isEmpty() ? "Invalid source-removal request." : problem)); return 1;
    }
    // Validate the whole requested set before making the first change. A race
    // during deletion still reports partial completion, never a false success.
    int removed = 0;
    for (const auto &target : targets) {
        if (!SourceRemoval::remove(target, nullptr, problem)) {
            std::fprintf(stderr, "%s\n", qPrintable(problem + (removed ? " Some system copies were already removed; refresh Settings." : ""))); return 1;
        }
        ++removed;
    }
    return 0;
}
