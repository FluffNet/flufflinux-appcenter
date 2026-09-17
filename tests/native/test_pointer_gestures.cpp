// Send real Qt native-touchpad events through the production QML handlers.
// No system input injection and no Flatpak operations.
#include <QtQuickTest/quicktest.h>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QNativeGestureEvent>
#include <QPointingDevice>

class PointerTests : public QObject {
    Q_OBJECT
    QPointingDevice touchpad{"Test touchpad", 12345, QInputDevice::DeviceType::TouchPad,
        QPointingDevice::PointerType::Finger, QInputDevice::Capability::Position,
        2, 0};
public:
    Q_INVOKABLE void gesture(QQuickItem *item, int type, qreal x, qreal y, qreal value = 0) {
        Q_ASSERT(item && item->window());
        const auto scene = item->mapToScene(QPointF(x, y));
        QNativeGestureEvent event(static_cast<Qt::NativeGestureType>(type), &touchpad, 2,
            scene, scene, item->window()->mapToGlobal(scene), value, {});
        QCoreApplication::sendEvent(item->window(), &event);
    }
public slots:
    void qmlEngineAvailable(QQmlEngine *engine) {
        engine->rootContext()->setContextProperty("nativeInput", this);
    }
};
QUICK_TEST_MAIN_WITH_SETUP(pointer_gestures, PointerTests)
#include "test_pointer_gestures.moc"
