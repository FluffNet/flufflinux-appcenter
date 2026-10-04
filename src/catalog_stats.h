#pragma once
#include <QObject>
#include <QVariantMap>
#include "flatpak_manager.h"

// QML-facing projection of the Rust popularity state.
class CatalogStats final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap counts READ counts NOTIFY changed)
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString fetchedAt READ fetchedAt NOTIFY changed)
public:
    explicit CatalogStats(FlatpakManager *manager, QObject *parent = nullptr);
    QVariantMap counts() const { return m_manager->popularity().value("counts").toMap(); }
    QString state() const { return m_manager->popularity().value("state").toString(); }
    QString fetchedAt() const { return m_manager->popularity().value("fetchedAt").toString(); }
    Q_INVOKABLE void loadPopularity() { m_manager->loadPopularity(); }
signals:
    void changed();
private:
    FlatpakManager *m_manager;
};
