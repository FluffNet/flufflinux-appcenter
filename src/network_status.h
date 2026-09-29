#pragma once
#include <QObject>
#include <QDBusConnection>
#include <QVariantMap>

// Read-only, event-driven NetworkManager observer. No connectivity probes,
// network configuration changes, authorization, or Internet requirement.
class NetworkStatus final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
public:
    explicit NetworkStatus(QObject *parent = nullptr,
                           const QDBusConnection &bus = QDBusConnection::systemBus());
    QString state() const { return m_state; }
    bool ready() const { return m_ready; }
    static QString classify(const QVariantMap &properties);
signals:
    void changed();
private slots:
    void refresh();
    void propertiesChanged(const QString &interface, const QVariantMap &values,
                           const QStringList &invalidated);
private:
    void publish(const QString &state);
    QDBusConnection m_bus;
    QString m_state = QStringLiteral("unknown");
    bool m_ready = false;
    quint64 m_generation = 0;
};
