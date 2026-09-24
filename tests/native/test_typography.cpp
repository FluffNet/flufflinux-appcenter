#include <QApplication>
#include <QFontDatabase>
#include <QFontInfo>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTimer>
#include <QImage>
#include <cassert>
#include <iostream>
#include "../../src/ui_typography.h"

static int checked = 0;
static int paintedLabels = 0;
static QString expectedFamily;
static QImage screenshot;
static QQuickWindow *testedWindow;

static void describe(const char *label, const QFont &font) {
    QFontInfo info(font);
    std::cout << label << ": requested=" << font.toString().toStdString()
              << "; resolved=" << info.family().toStdString() << '/' << info.styleName().toStdString()
              << " weight=" << info.weight() << " pixels=" << info.pixelSize() << std::endl;
}
static void inspect(QQuickItem *item) {
    const auto name = item->objectName();
    if (name == "installedSourceValue" || name == "installedVersionValue") {
        const auto font = item->property("font").value<QFont>();
        assert(QFontInfo(font).family() == expectedFamily);
        assert(item->property("renderType").toInt() == QQuickWindow::QtTextRendering);
        if (name == "installedSourceValue") assert(QFontInfo(font).weight() == QFont::Bold);
        ++checked;
        const auto pos = item->mapToScene(QPointF());
        // Check glyphs remain visible after scrolling to fractional physical-
        // pixel positions. Glyph-shape correctness is covered by the separate
        // TextInput parity test, not by assuming a particular antialias color.
        const qreal ratio = qreal(screenshot.width()) / testedWindow->width();
        const QRect rect(qRound(pos.x() * ratio), qRound(pos.y() * ratio),
                         qRound(item->width() * ratio), qRound(item->height() * ratio));
        const QRectF sceneRect(pos, item->size());
        bool unclipped = true;
        for (auto ancestor = item->parentItem(); ancestor; ancestor = ancestor->parentItem())
            if (ancestor->clip() && !ancestor->mapRectToScene(QRectF(QPointF(), ancestor->size())).contains(sceneRect))
                unclipped = false;
        if (item->isVisible() && unclipped && screenshot.rect().contains(rect)
            && pos.y() > 220) {
            int painted = 0;
            for (int y = rect.top(); y < rect.bottom(); ++y)
                for (int x = rect.left(); x < rect.right(); ++x) {
                    const auto pixel = screenshot.pixelColor(x, y);
                    if (pixel.red() > 100) ++painted;
                }
            if (!painted) {
                std::cerr << "No painted glyphs at " << rect.x() << ',' << rect.y() << ' '
                          << rect.width() << 'x' << rect.height() << "; image=" << screenshot.width() << 'x'
                          << screenshot.height() << std::endl;
                screenshot.save("target/typography-diagnostic.png");
            }
            assert(painted > 0);
            ++paintedLabels;
        }
    }
    for (auto child : item->childItems()) inspect(child);
}
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    assert(argc > 1);
    expectedFamily = QFontInfo(QFontDatabase::systemFont(QFontDatabase::GeneralFont)).family();
    configureDesktopTypography(app);
    describe("system", QFontDatabase::systemFont(QFontDatabase::GeneralFont));
    describe("application", app.font());
    QQmlApplicationEngine engine;
    engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (engine.rootObjects().isEmpty()) return 1;
    testedWindow = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    auto list = engine.rootObjects().first()->findChild<QQuickItem *>("installedList");
    assert(list);
    QTimer timer;
    int phase = 0;
    QObject::connect(&timer, &QTimer::timeout, &app, [&] {
        screenshot = testedWindow->grabWindow(); assert(!screenshot.isNull());
        checked = 0;
        paintedLabels = 0;
        inspect(testedWindow->contentItem());
        assert(checked >= 4);
        assert(paintedLabels >= 2);
        if (phase < 4) {
            testedWindow->resize(phase % 2 ? 1180 : 1041, phase % 2 ? 760 : 683);
            list->setProperty("contentY", (phase + 1) * 23.5);
            ++phase; return;
        }
        if (argc > 2) assert(screenshot.save(QString::fromLocal8Bit(argv[2])));
        std::cout << "PASS: system font/weight, scalable glyphs after repeated fractional scroll/resize; DPR="
                  << testedWindow->devicePixelRatio() << std::endl;
        app.quit();
    });
    timer.start(500);
    return app.exec();
}
