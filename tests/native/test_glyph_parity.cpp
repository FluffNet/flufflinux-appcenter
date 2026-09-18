#include <QApplication>
#include <QFontInfo>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlProperty>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <cmath>
#include <iostream>
#include "../../src/ui_typography.h"

static QQuickItem *findItem(QQuickItem *root, const QString &name) {
    if (root->objectName() == name) return root;
    for (auto child : root->childItems()) if (auto found = findItem(child, name)) return found;
    return nullptr;
}

// Compare the actual production label's pixels to a TextInput at the exact
// same baseline, font, color and physical position. A renderer-name or font-
// family assertion alone cannot catch the visually different 7 reported here.
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    if (argc < 2) return 2;
    configureDesktopTypography(app);
    QQmlApplicationEngine engine;
    engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (engine.rootObjects().isEmpty()) return 2;
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QQmlComponent inputComponent(&engine);
    inputComponent.setData("import QtQuick\nTextInput { readOnly: true; cursorVisible: false; autoScroll: false; padding: 0 }", QUrl());
    auto reference = qobject_cast<QQuickItem *>(inputComponent.create());
    if (!reference) return 2;
    reference->setVisible(false);
    reference->setParent(window);
    QQuickItem *target = nullptr;
    QImage actual;
    QRect region;
    int phase = 0;
    int scenario = 0;
    bool passed = true;
    const bool negativeControl = argc > 2 && QString::fromLocal8Bit(argv[2]) == "--native-labels";
    QTimer timer;
    QObject::connect(&timer, &QTimer::timeout, &app, [&] {
        if (phase == 0) {
            target = findItem(window->contentItem(), scenario < 3 ? "catalogCountLabel" : "installedSourceValue");
            auto search = findItem(window->contentItem(), "searchField");
            if (!target || !search) { app.exit(2); return; }
            if (scenario == 0) QQmlProperty::write(target, "text", "3297 applications");
            if (scenario == 1) QQmlProperty::write(target, "text", "7 applications");
            if (scenario == 2) QQmlProperty::write(target, "text", "0123456789");
            target->setProperty("color", QColor(Qt::white));
            if (negativeControl) target->setProperty("renderType", 1);
            const auto font = target->property("font").value<QFont>();
            auto inputFont = search->property("font").value<QFont>();
            inputFont.setWeight(font.weight());
            if (QFontInfo(font).family() != QFontInfo(inputFont).family()
                || QFontInfo(font).pixelSize() != QFontInfo(inputFont).pixelSize()) { app.exit(3); return; }
            // Keep the reference out of the label's Row/ColumnLayout: adding
            // it there would relayout the production label while measuring it.
            reference->setParentItem(window->contentItem());
            reference->setZ(1000);
            reference->setSize(target->size());
            reference->setProperty("font", inputFont);
            reference->setProperty("text", target->property("text"));
            reference->setProperty("color", target->property("color"));
            reference->setProperty("renderType", search->property("renderType"));
            reference->setOpacity(0); reference->setVisible(true);
            ++phase;
        } else if (phase == 1) {
            actual = window->grabWindow();
            const qreal ratio = qreal(actual.width()) / window->width();
            const auto position = target->mapToScene(QPointF());
            region = QRect(qFloor(position.x() * ratio), qFloor(position.y() * ratio),
                           qCeil(target->width() * ratio), qCeil(target->height() * ratio));
            // TextInput's baseline settles on its first polish, not at create().
            reference->setSize(target->size());
            reference->setPosition(QPointF(position.x(), position.y()
                + target->property("baselineOffset").toReal() - reference->property("baselineOffset").toReal()));
            if (reference->property("text") != target->property("text")) {
                std::cerr << "Reference and label text changed during setup" << std::endl;
                app.exit(4); return;
            }
            target->setOpacity(0); reference->setOpacity(1); ++phase;
        } else {
            const auto expected = window->grabWindow();
            long long difference = 0, signal = 0;
            const auto background = actual.pixelColor(region.topLeft());
            for (int y = region.top(); y <= region.bottom(); ++y)
                for (int x = region.left(); x <= region.right(); ++x) {
                    const auto a = actual.pixelColor(x, y), b = expected.pixelColor(x, y);
                    difference += std::abs(a.red() - b.red()) + std::abs(a.green() - b.green()) + std::abs(a.blue() - b.blue());
                    signal += std::abs(b.red() - background.red()) + std::abs(b.green() - background.green()) + std::abs(b.blue() - background.blue());
                }
            const double error = signal ? double(difference) / signal : 1;
            const bool matches = error < 0.025;
            passed &= matches;
            std::cout << (matches ? "PASS" : "FAIL") << " glyph parity: " << target->property("text").toString().toStdString()
                      << " relative pixel error=" << error << " DPR=" << window->devicePixelRatio() << std::endl;
            if (!matches) {
                actual.copy(region).save(QString("target/glyph-actual-%1.png").arg(scenario));
                expected.copy(region).save(QString("target/glyph-input-%1.png").arg(scenario));
            }
            target->setOpacity(1); reference->setVisible(false);
            if (++scenario == 4) { app.exit(passed ? 0 : 1); return; }
            phase = 0;
        }
    });
    timer.start(300);
    return app.exec();
}
