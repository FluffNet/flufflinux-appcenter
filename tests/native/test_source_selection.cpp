// The manager's real request routing with a no-op child executable. No event
// loop is run: installed lists, desktop caches and real workers never execute.
#include "../../src/flatpak_manager.h"
#include <QCoreApplication>
#include <cassert>
#include <cstdio>
int main(int argc, char **argv) {
    if (argc > 1 && QByteArray(argv[1]) == "--transaction-worker") return 0;
    if (argc > 1) return 2;
    QCoreApplication application(argc, argv);
    const QVariantMap stable{{"id", "org.example.SourceTest"}, {"name", "Source Test"},
        {"remote", "stable"}, {"sourceUrl", "https://example.org/stable"}, {"flatpakRef", "app/org.example.SourceTest/x86_64/stable"}};
    auto beta = stable;
    beta["remote"] = "beta"; beta["sourceUrl"] = "https://example.org/beta";
    beta["flatpakRef"] = "app/org.example.SourceTest/x86_64/beta";
    auto catalog = stable; catalog["sources"] = QVariantList{stable, beta};
    {
        FlatpakManager manager({catalog});
        manager.installApp(beta);
        assert(manager.jobs().size() == 1);
        const auto job = manager.jobs().first().toMap();
        assert(job["remote"] == beta["remote"] && job["flatpakRef"] == beta["flatpakRef"] && job["sourceUrl"] == beta["sourceUrl"]);
        assert(job["installation"] == "user");
    }
    for (const auto &field : {"remote", "sourceUrl", "flatpakRef"}) {
        FlatpakManager manager({catalog});
        int errors = 0;
        QObject::connect(&manager, &FlatpakManager::inputError, [&] { ++errors; });
        auto stale = beta; stale[field] = "changed";
        manager.installApp(stale);
        assert(manager.jobs().isEmpty() && errors == 1);
    }
    puts("PASS: selected source/ref/URL reach the worker unchanged; stale or forged source choices are rejected");
}
