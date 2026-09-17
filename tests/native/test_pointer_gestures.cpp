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
        2, 1};
    QPointingDevice mouse{"Test mouse", 12346, QInputDevice::DeviceType::Mouse,
        QPointingDevice::PointerType::Generic, QInputDevice::Capability::Position,
        1, 3};
public:
    Q_INVOKABLE void pointer(QQuickItem *item, int phase, qreal x, qreal y, bool fromTouchpad = false) {
        Q_ASSERT(item && item->window());
        const auto scene = item->mapToScene(QPointF(x, y));
        const auto type = phase == 0 ? QEvent::MouseButtonPress : phase == 1 ? QEvent::MouseMove : QEvent::MouseButtonRelease;
        QMouseEvent event(type, scene, scene, item->window()->mapToGlobal(scene),
            phase == 1 ? Qt::NoButton : Qt::LeftButton, phase == 2 ? Qt::NoButton : Qt::LeftButton,
            Qt::NoModifier, fromTouchpad ? &touchpad : &mouse);
        QCoreApplication::sendEvent(item->window(), &event);
    }
    Q_INVOKABLE void scroll(QQuickItem *item, qreal x, qreal y, int dx, int dy) {
        Q_ASSERT(item && item->window());
        const auto scene = item->mapToScene(QPointF(x, y));
        QWheelEvent event(scene, item->window()->mapToGlobal(scene), QPoint(dx, dy), QPoint(dx * 3, dy * 3),
            Qt::NoButton, Qt::NoModifier, Qt::ScrollUpdate, false, Qt::MouseEventNotSynthesized, &touchpad);
        QCoreApplication::sendEvent(item->window(), &event);
    }
    Q_INVOKABLE void mouseWheel(QQuickItem *item, qreal x, qreal y, int dx, int dy) {
        Q_ASSERT(item && item->window());
        const auto scene = item->mapToScene(QPointF(x, y));
        QWheelEvent event(scene, item->window()->mapToGlobal(scene), {}, QPoint(dx, dy),
            Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false, Qt::MouseEventNotSynthesized, &mouse);
        QCoreApplication::sendEvent(item->window(), &event);
    }
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
