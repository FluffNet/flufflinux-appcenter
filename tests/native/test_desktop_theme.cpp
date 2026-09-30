// Real KDE palettes and the production icon provider, no Flatpak operations.
#include "../../src/desktop_theme.h"
#include <KColorScheme>
#include <KSharedConfig>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QTimer>
#include <cassert>

class ThemeProbe final : public QObject {
    Q_OBJECT
public:
    explicit ThemeProbe(QJsonArray cases) : m_cases(cases) {}
    Q_INVOKABLE bool capture(QObject *object, const QString &path) {
        const auto window = qobject_cast<QQuickWindow *>(object);
        return window && window->grabWindow().save(path);
    }
    Q_INVOKABLE QVariantMap apply(int index) {
        if (index >= m_cases.size()) return {};
        const auto test = m_cases[index].toObject();
        const auto config = KSharedConfig::openConfig(test["config"].toString(), KConfig::SimpleConfig);
        const auto palette = KColorScheme::createApplicationPalette(config);
        qApp->setPalette(palette);
        auto result = test.toVariantMap();
        result["highlight"] = palette.color(QPalette::Highlight);
        result["link"] = palette.color(QPalette::Link);
        result["highlightedText"] = palette.color(QPalette::HighlightedText);
        return result;
    }
private:
    QJsonArray m_cases;
};

static void write(const QString &path, const QByteArray &data) {
    QFile file(path); assert(file.open(QIODevice::WriteOnly));
    assert(file.write(data) == data.size());
}
static QColor pixel(const QIcon &icon) { return icon.pixmap(32, 32).toImage().pixelColor(16, 16); }
static void testIcons() {
    QTemporaryDir themes;
    assert(themes.isValid());
    const auto searchPaths = QIcon::themeSearchPaths();
    const auto fallbackPaths = QIcon::fallbackSearchPaths();
    const auto original = QIcon::themeName();
    const auto fallbackTheme = QIcon::fallbackThemeName();
    QIcon::setThemeSearchPaths({themes.path()});
    QIcon::setFallbackSearchPaths({});
    QIcon::setFallbackThemeName("");
    QPixmap fallbackPixmap(32, 32); fallbackPixmap.fill(Qt::red);
    const QIcon fallback(fallbackPixmap);
    for (const auto &name : {QString("green"), QString("blue"), QString("empty")}) {
        const auto path = themes.path() + '/' + name;
        assert(QDir().mkpath(path + "/32x32/apps"));
        write(path + "/index.theme", "[Icon Theme]\nName=" + name.toUtf8()
            + "\nDirectories=32x32/apps\n[32x32/apps]\nSize=32\nType=Fixed\nContext=Applications\n");
        if (name != "empty") {
            QPixmap pixmap(32, 32); pixmap.fill(QColor(name));
            assert(pixmap.save(path + "/32x32/apps/flufflinux-appcenter.png"));
        }
    }
    QIcon::setThemeName("green");
    DesktopTheme theme(fallback);
    ThemeIconProvider provider(fallback);
    auto color = [&] { return provider.requestPixmap("flufflinux-appcenter?theme=1", nullptr, QSize(32, 32)).toImage().pixelColor(16, 16); };
    assert(color() == QColor("green"));
    assert(pixel(qApp->windowIcon()) == QColor("green"));
    QIcon::setThemeName("blue");
    const auto before = theme.revision();
    // Use KDE's actual reload signal. QML URLs must change even when an
    // already-open app has images cached under the same icon name.
    KIconLoader::global()->iconChanged(KIconLoader::Desktop);
    assert(theme.revision() > before);
    assert(color() == QColor("blue"));
    assert(pixel(qApp->windowIcon()) == QColor("blue"));
    QIcon::setThemeName("empty");
    KIconLoader::global()->iconChanged(KIconLoader::Desktop);
    assert(color() == QColor(Qt::red));
    assert(pixel(qApp->windowIcon()) == QColor(Qt::red));
    const auto paletteBefore = theme.revision();
    QEvent paletteEvent(QEvent::ApplicationPaletteChange);
    QCoreApplication::sendEvent(qApp, &paletteEvent);
    assert(theme.revision() > paletteBefore);
    QIcon::setThemeSearchPaths(searchPaths);
    QIcon::setFallbackSearchPaths(fallbackPaths);
    QIcon::setFallbackThemeName(fallbackTheme);
    QIcon::setThemeName(original.isEmpty() ? QStringLiteral("breeze") : original);
    qInfo("PASS: themed icon, live KDE icon reload, bundled fallback, palette invalidation");
}

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QCoreApplication::setApplicationName("appcenter-theme-test");
    if (argc == 1) { testIcons(); return 0; }
    if (QIcon::themeName().isEmpty()) QIcon::setThemeName("breeze");
    assert(argc == 4);
    const QString root = QString::fromLocal8Bit(argv[1]);
    QFile cases(QString::fromLocal8Bit(argv[2])); assert(cases.open(QIODevice::ReadOnly));
    ThemeProbe probe(QJsonDocument::fromJson(cases.readAll()).array());
    const QIcon fallback(root + "/assets/flufflinux-appcenter.svg");
    DesktopTheme theme(fallback);
    QQmlApplicationEngine engine;
    engine.addImageProvider("icon", new ThemeIconProvider(fallback));
    engine.rootContext()->setContextProperty("fluffDesktopTheme", &theme);
    engine.rootContext()->setContextProperty("themeProbe", &probe);
    engine.rootContext()->setContextProperty("themeOutput", QString::fromLocal8Bit(argv[3]));
    QFile catalog(QString::fromLocal8Bit(argv[3]) + "/catalog.json");
    assert(catalog.open(QIODevice::ReadOnly));
    engine.rootContext()->setContextProperty("themeCatalog", QJsonDocument::fromJson(catalog.readAll()).array().toVariantList());
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);
    QObject::connect(&engine, &QQmlEngine::exit, &app, &QCoreApplication::exit);
    engine.load(QUrl::fromLocalFile(root + "/tests/integration/ThemeSmoke.qml"));
    assert(!engine.rootObjects().isEmpty());
    QTimer::singleShot(180000, &app, [] { qFatal("Theme test timed out"); });
    return app.exec();
}

#include "test_desktop_theme.moc"
