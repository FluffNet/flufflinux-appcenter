// Diagnostic bootstrap only: compare the former async theme-provider path
// with the GUI-thread path. Never installed or run against Flatpak state.
#include "../../src/desktop_theme.h"
#include "../../src/ui_typography.h"
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QFile>
#include <QDir>
#include <QTemporaryDir>
#include <cassert>
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    assert(argc == 2);
    configureDesktopTypography(app);
    QTemporaryDir icons;
    assert(icons.isValid());
    const auto directory = icons.path() + "/probe/32x32/apps";
    assert(QDir().mkpath(directory));
    QFile index(icons.path() + "/probe/index.theme");
    assert(index.open(QIODevice::WriteOnly));
    index.write("[Icon Theme]\nName=probe\nDirectories=32x32/apps\n[32x32/apps]\nSize=32\nType=Scalable\nMinSize=16\nMaxSize=128\nContext=Applications\n");
    index.close();
    QFile svg(directory + "/font-probe.svg");
    assert(svg.open(QIODevice::WriteOnly));
    svg.write("<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'><text x='2' y='40' font-size='32'>Aa</text></svg>");
    svg.close();
    QIcon::setThemeSearchPaths({icons.path()});
    QIcon::setThemeName("probe");
    QQmlApplicationEngine engine;
    engine.addImageProvider("icon", new ThemeIconProvider(QIcon(directory + "/font-probe.svg")));
    engine.rootContext()->setContextProperty("asyncTheme", qEnvironmentVariableIsSet("APPCENTER_TEST_OLD_ASYNC_ICONS"));
    engine.rootContext()->setContextProperty("probeIterations", qEnvironmentVariableIsSet("APPCENTER_TEST_ICON_ITERATIONS")
        ? qBound(1, qEnvironmentVariableIntValue("APPCENTER_TEST_ICON_ITERATIONS"), 10000) : 600);
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);
    QObject::connect(&engine, &QQmlEngine::exit, &app, &QCoreApplication::exit);
    engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    assert(!engine.rootObjects().isEmpty());
    QTimer::singleShot(300000, &app, [] { qFatal("Theme thread probe timed out"); });
    return app.exec();
}
