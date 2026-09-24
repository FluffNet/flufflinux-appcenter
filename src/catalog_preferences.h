#pragma once
#include <QObject>
#include <QSettings>
#include <QStringList>
#include <memory>

// Shares the existing App Center INI without changing window/source settings.
// An empty path gives read-only UI fixtures an isolated, in-memory preference.
class CatalogPreferences final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString homeSort READ homeSort WRITE setHomeSort NOTIFY homeSortChanged)
public:
    explicit CatalogPreferences(const QString &path, QObject *parent = nullptr) : QObject(parent) {
        if (path.isEmpty()) return;
        m_settings = std::make_unique<QSettings>(path, QSettings::IniFormat);
        const auto saved = m_settings->value("Catalog/homeSort", m_homeSort).toString();
        if (sortKeys().contains(saved)) m_homeSort = saved;
    }
    static QStringList sortKeys() {
        return {"name-asc", "name-desc", "popularity-desc", "popularity-asc",
                "size-asc", "size-desc", "release-desc", "release-asc"};
    }
    QString homeSort() const { return m_homeSort; }
    void setHomeSort(const QString &value) {
        if (value == m_homeSort || !sortKeys().contains(value)) return;
        m_homeSort = value;
        if (m_settings) {
            m_settings->setValue("Catalog/homeSort", value);
            m_settings->sync(); // Atomic save, preserving all unrelated INI keys.
            if (m_settings->status() != QSettings::NoError)
                qWarning("Cannot save App Center catalog preferences.");
        }
        emit homeSortChanged();
    }
signals:
    void homeSortChanged();
private:
    std::unique_ptr<QSettings> m_settings;
    QString m_homeSort = "popularity-desc";
};
