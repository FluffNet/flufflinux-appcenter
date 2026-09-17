// Standalone, read-only tests. Include the implementation to exercise the
// metadata calculator with synthetic records, without a second public API.
#include "../../src/flatpak_sizes.cpp"
#include "../../src/transaction_progress.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <cassert>
#include <cstdio>

void record(Lookup &lookup, const QString &ref, quint64 size, const char *metadata) {
    if (lookup.sources.isEmpty()) lookup.sources.append({"test", "https://example.org", {}, g_ptr_array_new_with_free_func(g_object_unref)});
    g_autoptr(GBytes) bytes = g_bytes_new(metadata, strlen(metadata));
    auto object = FLATPAK_REMOTE_REF(g_object_new(FLATPAK_TYPE_REMOTE_REF,
        "name", ref.section('/', 1, 1).toUtf8().constData(),
        "arch", ref.section('/', 2, 2).toUtf8().constData(),
        "branch", ref.section('/', 3, 3).toUtf8().constData(),
        "kind", ref.startsWith("app/") ? FLATPAK_REF_KIND_APP : FLATPAK_REF_KIND_RUNTIME,
        "download-size", size, "metadata", bytes, nullptr));
    g_ptr_array_add(lookup.sources[0].owned, object);
    lookup.sources[0].refs[ref] = object;
}

int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    if (argc == 2 && QString::fromUtf8(argv[1]) == "--installed") {
        QElapsedTimer timer; timer.start();
        QVariantList checked;
        auto verifyInstallation = [&](FlatpakInstallation *installation, const QString &scope) {
            g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs_by_kind(installation, FLATPAK_REF_KIND_APP, nullptr, nullptr);
            for (guint i = 0; refs && i < refs->len; ++i) {
                auto ref = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, i));
                const auto id = text(flatpak_ref_get_name(FLATPAK_REF(ref)));
                QVariantMap app{{"id", id}, {"installation", scope},
                    {"installedArch", text(flatpak_ref_get_arch(FLATPAK_REF(ref)))},
                    {"installedBranch", text(flatpak_ref_get_branch(FLATPAK_REF(ref)))}};
                const auto bytes = flatpak_installed_ref_get_installed_size(ref);
                quint64 sortBytes = 0;
                const auto size = localInstalledFlatpakSize(app, &sortBytes);
                assert(!size.isEmpty() && size == downloadSizeText(bytes));
                assert(sortBytes == bytes);
                app["id"] = id + ".desktop";
                assert(localInstalledFlatpakSize(app) == size);
                app["installedBranch"] = "appcenter-nonexistent-test-branch";
                assert(localInstalledFlatpakSize(app, &sortBytes).isEmpty());
                assert(sortBytes == 0);
                checked.append(QVariantMap{{"id", id}, {"scope", scope}, {"bytes", double(bytes)}, {"size", size}});
            }
        };
        g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
        if (user) verifyInstallation(user, "user");
        g_autoptr(GPtrArray) systems = flatpak_get_system_installations(nullptr, nullptr);
        for (guint i = 0; systems && i < systems->len; ++i) {
            auto installation = FLATPAK_INSTALLATION(g_ptr_array_index(systems, i));
            const auto id = text(flatpak_installation_get_id(installation));
            verifyInstallation(installation, id == "default" ? "system" : id);
        }
        puts(QJsonDocument::fromVariant(QVariantMap{{"apps", checked}, {"elapsedMs", timer.elapsed()}}).toJson(QJsonDocument::Compact).constData());
        return 0;
    }
    if (argc > 1) {
        QElapsedTimer timer; timer.start();
        auto sizes = localFlatpakSizes({{"id", QString::fromUtf8(argv[1])}, {"remote", "flathub"}});
        sizes["elapsedMs"] = timer.elapsed();
        // Compare the real metadata estimate with a single-operation transfer
        // total: identical bytes must never switch from GiB to GB across the UI.
        if (sizes.contains("appBytes")) {
            const auto progress = transactionStages({QVariantMap{{"action", "install"},
                {"downloadBytes", sizes["appBytes"]}, {"downloadProgress", 0.5}}}, "download");
            assert(sizes["appSize"] == progress["downloadTotalSize"]);
            sizes["singleAppProgressTotal"] = progress["downloadTotalSize"];
        }
        puts(QJsonDocument::fromVariant(sizes).toJson(QJsonDocument::Compact).constData());
        return sizes["state"] == "ready" ? 0 : 1;
    }
    const QString app = "app/org.example.App/x86_64/stable";
    assert(localInstalledFlatpakSize({}).isEmpty());
    quint64 unknownBytes = 123;
    assert(localInstalledFlatpakSize({}, &unknownBytes).isEmpty());
    assert(unknownBytes == 0);
    assert(localInstalledFlatpakSize({{"id", "org.example.App"}, {"installation", "user"}}).isEmpty());
    const QString runtime = "runtime/org.example.Platform/x86_64/1";
    const QString locale = "runtime/org.example.App.Locale/x86_64/stable";
    Lookup lookup;
    record(lookup, app, 100, "[Application]\nruntime=org.example.Platform/x86_64/1\n[Extension org.example.App.Locale]\n[Extension org.example.App.Debug]\nno-autodownload=true\n");
    record(lookup, runtime, 400, "[Runtime]\nname=org.example.Platform\n");
    record(lookup, locale, 10, "[Runtime]\nname=org.example.App.Locale\n");
    record(lookup, "runtime/org.example.App.Debug/x86_64/stable", 2000, "[Runtime]\nname=org.example.App.Debug\n");
    auto calculate = [&] { lookup.total = 0; lookup.complete = true; lookup.visited.clear(); lookup.add(app, 0, true); };
    calculate(); assert(lookup.complete && lookup.total == 510);
    lookup.installed.insert(runtime);
    calculate(); assert(lookup.complete && lookup.total == 110);
    lookup.installed.insert(locale);
    calculate(); assert(lookup.complete && lookup.total == 100);
    lookup.installed.clear(); lookup.sources[0].refs.remove(runtime);
    calculate(); assert(!lookup.complete); // Never pretend missing metadata costs zero.
    record(lookup, runtime, 400, "[Runtime]\n[Extension org.example.App.Locale]\nversion=stable\n");
    calculate(); assert(lookup.complete && lookup.total == 510); // Shared dependency only once.
    record(lookup, app, 100, "[Application]\n[Extension org.example.GL]\nsubdirectories=true\nno-autodownload=true\ndownload-if=active-gl-driver\n");
    record(lookup, "runtime/org.example.GL.default/x86_64/stable", 20, "[Runtime]\nname=org.example.GL.default\n");
    record(lookup, "runtime/org.example.GL.nvidia-old/x86_64/stable", 500, "[Runtime]\nname=org.example.GL.nvidia-old\n");
    record(lookup, "runtime/org.example.GL.Debug.default/x86_64/stable", 2000, "[Runtime]\nname=org.example.GL.Debug.default\n");
    lookup.driversRead = true; lookup.glDrivers = {"default"};
    calculate(); assert(lookup.complete && lookup.total == 120);
    puts("PASS: missing/installed dependencies, optional debug, shared dependencies, and matching graphics extensions");
}
