#pragma once
#include <QObject>
#include <QStringList>
#include "rust_backend.h"

// QML property adapter. Rust validates and atomically saves the preference.
class CatalogPreferences final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString homeSort READ homeSort WRITE setHomeSort NOTIFY homeSortChanged)
public:
    explicit CatalogPreferences(const QString &path, QObject *parent = nullptr)
        : QObject(parent), m_path(path) {
        m_homeSort = rustUtility({{"operation", "sort-read"}, {"path", path}})["value"].toString();
    }
    QString homeSort() const { return m_homeSort; }
    void setHomeSort(const QString &value) {
        if (value == m_homeSort) return;
        const auto result = rustUtility({{"operation", "sort-save"}, {"path", m_path}, {"value", value}});
        if (!result["valid"].toBool()) return;
        m_homeSort = result["value"].toString();
        if (!result["saved"].toBool()) qWarning("Cannot save App Center catalog preferences.");
        emit homeSortChanged();
    }
signals:
    void homeSortChanged();
private:
    QString m_path;
    QString m_homeSort = "popularity-desc";
};
