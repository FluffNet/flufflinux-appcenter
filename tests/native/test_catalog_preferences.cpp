#include "../../src/catalog_preferences.h"
#include <QGuiApplication>
#include <QTemporaryDir>
#include <QFileInfo>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <cassert>
#include <iostream>

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    QTemporaryDir directory;
    assert(directory.isValid());
    const auto path = directory.path() + "/config/flufflinux-appcenter.conf";
    {
        CatalogPreferences empty(path);
        assert(empty.homeSort() == "popularity-desc");
        assert(!QFileInfo::exists(path)); // Merely reading does not create settings.
        empty.setHomeSort("invalid");
        assert(empty.homeSort() == "popularity-desc");
    }
    QSettings stored(path, QSettings::IniFormat);
    stored.setValue("Window/width", 1180);
    stored.setValue("Window/maximized", true);
    stored.setValue("Other/retain", "yes"); stored.sync();
    for (const auto &key : CatalogPreferences::sortKeys()) {
        CatalogPreferences current(path);
        current.setHomeSort(key);
        CatalogPreferences restarted(path);
        assert(restarted.homeSort() == key);
        stored.sync();
        assert(stored.value("Catalog/homeSort").toString() == key);
        assert(stored.value("Window/width").toInt() == 1180);
        assert(stored.value("Window/maximized").toBool());
        assert(stored.value("Other/retain").toString() == "yes");
    }
    stored.setValue("Catalog/homeSort", "bad-value"); stored.sync();
    assert(CatalogPreferences(path).homeSort() == "popularity-desc");
    CatalogPreferences isolated(QString{});
    isolated.setHomeSort("name-asc");
    stored.sync();
    assert(stored.value("Catalog/homeSort") == "bad-value"); // Fixtures cannot change the real config.
    if (argc > 1) {
        stored.setValue("Catalog/homeSort", "name-desc"); stored.sync();
        for (int run = 0; run < 2; ++run) {
            CatalogPreferences preferences(path);
            QQmlApplicationEngine engine;
            engine.rootContext()->setContextProperty("fluffWindowManaged", true);
            engine.rootContext()->setContextProperty("fluffCatalogPreferences", &preferences);
            engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
            assert(!engine.rootObjects().isEmpty());
            auto stack = engine.rootObjects().first()->findChild<QObject *>("navigationStack");
            assert(stack);
            auto page = stack->property("currentItem").value<QObject *>();
            assert(page && page->property("catalogSortIndex").toInt() == (run ? 5 : 1));
            assert(page->property("installedSortIndex").toInt() == 0);
            assert(page->setProperty("catalogSortIndex", 5));
            assert(preferences.homeSort() == "size-desc");
        }
    }
    std::cout << "PASS: popularity default, all saved sort orders, invalid fallback, unrelated keys, fixture isolation, real QML restore/save/restart\n";
}
