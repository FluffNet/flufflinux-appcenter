#include <QApplication>
#include <QFontInfo>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <iostream>
#include "../../src/ui_typography.h"

static void inspect(QQuickItem *item) {
    if (item->objectName().startsWith("compare")) {
        const auto font = item->property("font").value<QFont>();
        std::cout << item->objectName().toStdString() << " font=" << font.toString().toStdString()
                  << " resolved=" << QFontInfo(font).family().toStdString()
                  << " render=" << item->property("renderType").toInt()
                  << " position=" << item->mapToScene(QPointF()).x() << ',' << item->mapToScene(QPointF()).y() << std::endl;
    }
    for (auto child : item->childItems()) inspect(child);
}
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    configureDesktopTypography(app);
    QQmlApplicationEngine engine;
    engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (engine.rootObjects().isEmpty()) return 1;
    auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QTimer::singleShot(1500, &app, [&] {
        inspect(window->contentItem());
        if (!window->grabWindow().save(QString::fromLocal8Bit(argv[2]))) app.exit(2);
        else app.quit();
    });
    return app.exec();
}
