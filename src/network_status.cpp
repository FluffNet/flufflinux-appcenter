#include "network_status.h"
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QTimer>

namespace {
const QString service = QStringLiteral("org.freedesktop.NetworkManager");
const QString path = QStringLiteral("/org/freedesktop/NetworkManager");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");
}

QString NetworkStatus::classify(const QVariantMap &properties) {
    // NMState, not NMConnectivityState: Connectivity=NONE can also mean a
    // working LAN with no default Internet route. Never block that connection.
    // UNKNOWN/missing NM is not evidence that the machine is offline.
    const uint state = properties.value("State").toUInt();
    const uint connectivity = properties.value("Connectivity").toUInt();
    switch (state) {
    case 10: // Networking disabled/asleep.
    case 20: // No active network connection (including no network interfaces).
        return QStringLiteral("offline");
    case 30: // Disconnecting.
    case 40: // Connecting; do not lock out a connection still being established.
        return QStringLiteral("connecting");
    case 50: // CONNECTED_LOCAL: LAN only, no default route.
        return QStringLiteral("local");
    case 60: // CONNECTED_SITE: default route, Internet check did not succeed.
    case 70: // CONNECTED_GLOBAL.
        if (connectivity == 2) return QStringLiteral("portal");
        if (state == 60 || connectivity == 3) return QStringLiteral("limited");
        return QStringLiteral("online");
    default:
        return QStringLiteral("unknown");
    }
}

NetworkStatus::NetworkStatus(QObject *parent, const QDBusConnection &bus)
    : QObject(parent), m_bus(bus) {
    m_bus.connect(service, path, propertiesInterface, "PropertiesChanged", this,
                  SLOT(propertiesChanged(QString,QVariantMap,QStringList)));
    auto watcher = new QDBusServiceWatcher(service, m_bus,
        QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
            [this](const QString &, const QString &, const QString &owner) {
        ++m_generation; // Ignore a reply from the previous daemon instance.
        publish(QStringLiteral("unknown"));
        if (!owner.isEmpty()) refresh();
    });
    QTimer::singleShot(0, this, &NetworkStatus::refresh);
}

void NetworkStatus::propertiesChanged(const QString &interface, const QVariantMap &values,
                                      const QStringList &invalidated) {
    if (interface != service) return;
    for (const auto &key : {QStringLiteral("State"), QStringLiteral("Connectivity")}) {
        if (values.contains(key) || invalidated.contains(key)) { refresh(); return; }
    }
}

void NetworkStatus::refresh() {
    const auto generation = ++m_generation;
    auto request = QDBusMessage::createMethodCall(service, path, propertiesInterface, "GetAll");
    request.setAutoStartService(false);
    request << service;
    auto pending = new QDBusPendingCallWatcher(m_bus.asyncCall(request, 2500), this);
    connect(pending, &QDBusPendingCallWatcher::finished, this,
            [this, generation](QDBusPendingCallWatcher *replyWatcher) {
        const QDBusPendingReply<QVariantMap> reply = *replyWatcher;
        replyWatcher->deleteLater();
        if (generation != m_generation) return;
        publish(reply.isError() ? QStringLiteral("unknown") : classify(reply.value()));
    });
}

void NetworkStatus::publish(const QString &state) {
    if (m_ready && m_state == state) return;
    m_ready = true;
    m_state = state;
    emit changed();
}
