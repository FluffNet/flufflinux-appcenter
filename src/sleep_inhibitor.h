#pragma once
#include <QObject>
#include <QPointer>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <optional>

// KDE PowerDevil's standard suspend inhibitor, acquired immediately rather
// than after KInhibitionJobTracker's ten-second grace period. This does not
// disable screen locking or keep the display lit. The bus also releases it
// automatically if the service crashes or the desktop session ends.
class SleepInhibitor final : public QObject {
public:
    explicit SleepInhibitor(QObject *parent = nullptr) : QObject(parent),
        m_watch(service(), QDBusConnection::sessionBus(), QDBusServiceWatcher::WatchForOwnerChange, this) {
        connect(&m_watch, &QDBusServiceWatcher::serviceOwnerChanged, this,
            [this](const QString &, const QString &, const QString &) {
                ++m_generation; m_pending = false; m_cookie.reset(); m_owner.clear();
                if (m_wanted) acquire();
            });
    }
    ~SleepInhibitor() override { release(); }
    bool requested() const { return m_wanted; }
    void setActive(bool active) {
        m_wanted = active;
        if (active) acquire(); else release();
    }
private:
    static QString service() { return QStringLiteral("org.freedesktop.PowerManagement.Inhibit"); }
    static QDBusMessage call(const QString &owner, const QString &method) {
        return QDBusMessage::createMethodCall(owner, "/org/freedesktop/PowerManagement/Inhibit", service(), method);
    }
    static void uninhibit(const QString &owner, uint cookie) {
        auto message = call(owner, "UnInhibit"); message << cookie;
        QDBusConnection::sessionBus().asyncCall(message);
    }
    void acquire() {
        if (m_cookie || m_pending) return;
        const auto owner = QDBusConnection::sessionBus().interface()->serviceOwner(service());
        if (!owner.isValid() || owner.value().isEmpty()) {
            qWarning("App Center cannot inhibit sleep: KDE power management is unavailable."); return;
        }
        m_pending = true;
        auto message = call(owner.value(), "Inhibit");
        message << QStringLiteral("App Center") << tr("Installing, updating or removing apps");
        auto watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message));
        QPointer<SleepInhibitor> guard(this);
        const auto generation = m_generation;
        connect(watcher, &QDBusPendingCallWatcher::finished, watcher, [guard, watcher, generation, owner = owner.value()] {
            const QDBusPendingReply<uint> reply = *watcher;
            watcher->deleteLater();
            if (!guard || generation != guard->m_generation) {
                if (!reply.isError()) uninhibit(owner, reply.value());
                return;
            }
            guard->m_pending = false;
            if (reply.isError()) { qWarning("App Center could not inhibit sleep: %s", qPrintable(reply.error().message())); return; }
            if (!guard->m_wanted) { uninhibit(owner, reply.value()); return; }
            guard->m_owner = owner; guard->m_cookie = reply.value();
        });
    }
    void release() {
        if (m_cookie) { uninhibit(m_owner, *m_cookie); m_cookie.reset(); }
    }
    QDBusServiceWatcher m_watch;
    QString m_owner;
    std::optional<uint> m_cookie;
    quint64 m_generation = 0;
    bool m_wanted = false, m_pending = false;
};
