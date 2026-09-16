// VM integration probe: keep a real KDE icon loader alive across an install.
// Run before installing the absent test app through App Center. This probe
// never installs/removes files and succeeds only on KDE's reload notification.
#include <KIconLoader>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QTimer>
#include <iostream>

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    if (argc != 2) return 2;
    const auto name = QString::fromLocal8Bit(argv[1]);
    auto *loader = KIconLoader::global();
    if (!loader->iconPath(name, KIconLoader::Desktop, true).isEmpty()) {
        std::cerr << "Refusing probe: the test icon is already available\n";
        return 2;
    }
    // Also prime Qt's cached lookup, as used by themed launcher icons.
    QIcon::fromTheme(name).pixmap(48, 48);
    std::cout << "ICON_PRIMED_MISSING " << name.toStdString() << std::endl;
    QObject::connect(loader, &KIconLoader::iconChanged, &app, [&](int) {
        QTimer::singleShot(0, &app, [&] {
            const auto path = loader->iconPath(name, KIconLoader::Desktop, true);
            if (path.isEmpty()) return;
            if (!QFileInfo::exists(path) || QIcon::fromTheme(name).pixmap(48, 48).isNull()) {
                std::cerr << "ICON_RELOAD_FAIL: icon is still unusable after notification\n";
                app.exit(1);
                return;
            }
            std::cout << "ICON_RELOAD_PASS: running KDE/Qt loader resolved " << path.toStdString() << std::endl;
            app.quit();
        });
    });
    QTimer::singleShot(180000, &app, [&] {
        std::cerr << "ICON_RELOAD_FAIL: no usable icon reload notification\n";
        app.exit(1);
    });
    return app.exec();
}
