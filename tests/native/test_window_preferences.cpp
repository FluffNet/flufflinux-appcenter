#include "../../src/window_preferences.h"
#include <QTemporaryDir>
#include <QTest>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <cassert>
#include <cstdio>

static void settle() { QTest::qWait(350); }

int main(int argc, char **argv) {
    QGuiApplication application(argc, argv);
    application.setQuitOnLastWindowClosed(false);
    QTemporaryDir directory;
    assert(directory.isValid());
    const auto path = directory.path() + "/config/flufflinux-appcenter.conf";
    assert(WindowPreferences::defaultPath() == QDir::homePath() + "/.config/flufflinux-appcenter.conf");
    {
        WindowPreferences preferences(path);
        const auto launch = preferences.launchFor(QSize(1920, 1080));
        assert(launch.maximized && launch.normalSize == QSize(1180, 760));
        assert(!QFileInfo::exists(path)); // A read-only plan never creates config.
        QQuickWindow window;
        window.setTitle("App Center window settings test");
        preferences.restore(&window);
        settle();
        QSettings stored(path, QSettings::IniFormat);
        assert(stored.value("Window/maximized").toBool());
        assert(stored.value("Window/width").toInt() == 1180);
        window.showNormal();
        settle();
        window.resize(780, 550);
        settle();
        stored.sync();
        assert(!stored.value("Window/maximized").toBool());
        assert(stored.value("Window/width").toInt() == 780);
        assert(stored.value("Window/height").toInt() == 550);
        window.showMaximized();
        settle();
        stored.sync();
        assert(stored.value("Window/maximized").toBool());
        assert(stored.value("Window/width").toInt() == 780);
        assert(stored.value("Window/height").toInt() == 550);
        window.showMinimized(); settle(); preferences.flush(); stored.sync();
        assert(stored.value("Window/maximized").toBool());
        window.showNormal(); settle(); window.resize(790, 560); settle();
        window.showMinimized(); settle(); preferences.flush(); stored.sync();
        assert(!stored.value("Window/maximized").toBool());
        assert(stored.value("Window/width").toInt() == 790);
        window.close();
    }
    {
        WindowPreferences restarted(path);
        assert(!restarted.launchFor(QSize(1920, 1080)).maximized);
        assert(restarted.launchFor(QSize(1920, 1080)).normalSize == QSize(790, 560));
        assert(!restarted.launchFor(QSize(790, 560)).maximized);
        assert(restarted.launchFor(QSize(789, 560)).maximized);
        assert(restarted.launchFor(QSize(790, 559)).maximized);
        const auto small = restarted.launchFor(QSize(640, 480));
        assert(small.maximized && small.initialSize == QSize(640, 480));
        assert(small.normalSize == QSize(790, 560)); // Don't lose the normal size.
        QQuickWindow restored;
        restarted.restore(&restored); settle();
        assert(restored.visibility() == QWindow::Windowed);
        assert(restored.size() == QSize(790, 560));
        restored.close();
    }
    {
        const auto oversizedPath = directory.path() + "/oversized.conf";
        QSettings stored(oversizedPath, QSettings::IniFormat);
        stored.setValue("Window/width", 10000);
        stored.setValue("Window/height", 9000);
        stored.setValue("Window/maximized", false);
        stored.sync();
        WindowPreferences preferences(oversizedPath);
        QQuickWindow window;
        preferences.restore(&window); settle();
        assert(window.visibility() == QWindow::Maximized);
        stored.sync();
        assert(stored.value("Window/maximized").toBool());
        assert(stored.value("Window/width").toInt() == 10000);
        window.close();
    }
    if (argc > 1) {
        // Exercise the real Main.qml hidden-before-restore path as well as
        // the native controller. No backend and a temporary config only.
        const auto mainPath = directory.path() + "/main.conf";
        for (const int run : {0, 1, 2}) {
            WindowPreferences preferences(mainPath);
            QQmlApplicationEngine engine;
            engine.rootContext()->setContextProperty("fluffWindowManaged", true);
            engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
            assert(!engine.rootObjects().isEmpty());
            const auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
            assert(window && !window->isVisible());
            preferences.restore(window); settle();
            assert(window->visibility() == (run != 1 ? QWindow::Maximized : QWindow::Windowed));
            if (run == 0) {
                window->showNormal(); settle(); window->resize(790, 560); settle();
            } else if (run == 1) {
                assert(window->size() == QSize(790, 560));
                window->showMaximized(); settle();
            }
            window->close();
        }
        puts("PASS: real Main.qml restores before showing, remembers normal size, and remembers switching back to maximized");
    }
    {
        QSettings manual(path, QSettings::IniFormat);
        manual.setValue("Window/width", "broken");
        manual.setValue("Window/height", -1);
        manual.setValue("Window/maximized", "broken");
        manual.setValue("Other/retain", "yes");
        manual.sync();
        WindowPreferences preferences(path);
        const auto launch = preferences.launchFor(QSize(1920, 1080));
        assert(launch.maximized && launch.normalSize == QSize(1180, 760));
        QQuickWindow window;
        window.setTitle("App Center window settings test");
        preferences.restore(&window); settle(); preferences.flush();
        manual.sync();
        assert(manual.value("Other/retain").toString() == "yes");
        window.close();
    }
    puts("PASS: default/creation, live resize and state persistence, restart, minimized exclusion, screen fit, invalid values, unrelated keys");
}
