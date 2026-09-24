#pragma once
#include <QObject>
#include <QVariantMap>
#include <QJsonObject>
#include <QDateTime>
#include <QNetworkAccessManager>

// Presentation metadata only. No installed-app IDs are sent and this object
// cannot start a Flatpak check, install, update, or source operation.
class CatalogStats final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap counts READ counts NOTIFY changed)
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString fetchedAt READ fetchedAt NOTIFY changed)
public:
    explicit CatalogStats(QObject *parent = nullptr);
    QVariantMap counts() const { return m_counts.toVariantMap(); }
    QString state() const { return m_state; }
    QString fetchedAt() const { return m_fetchedAt.toString(Qt::ISODate); }
    Q_INVOKABLE void loadPopularity();
    static QJsonObject validCounts(const QJsonObject &raw);
    static bool readPage(const QByteArray &bytes, int page, int &totalPages, QJsonObject &counts);
signals:
    void changed();
private:
    void fetchPage(int page);
    void failed();
    QString cachePath() const;
    QNetworkAccessManager m_network;
    QJsonObject m_counts, m_pending;
    QString m_state = "idle";
    QDateTime m_fetchedAt, m_lastAttempt;
    int m_totalPages = 0;
};
