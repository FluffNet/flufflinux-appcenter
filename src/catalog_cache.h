#pragma once
#include <QString>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

namespace CatalogCache {
// Version 1 only rebuilt local metadata and is not proof of a source refresh.
constexpr int version = 2;
constexpr qint64 lifetimeSeconds = 12 * 60 * 60;
constexpr qint64 maximumBytes = 64 * 1024 * 1024;
struct Entry {
    QVariantList apps;
    QDateTime savedAt;
    bool valid = false;
};
inline QString defaultPath() {
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/application-list.json";
}
inline bool fresh(const QDateTime &savedAt, const QDateTime &now = QDateTime::currentDateTimeUtc()) {
    // Use a rolling lifetime, not a midnight cutoff. Clock rollback cannot make a
    // future-dated cache stay fresh indefinitely.
    return savedAt.isValid() && savedAt <= now && savedAt.secsTo(now) < lifetimeSeconds;
}
inline Entry read(const QString &path, const QString &fingerprint,
                  const QDateTime &now = QDateTime::currentDateTimeUtc()) {
    QFile file(path);
    if (path.isEmpty() || fingerprint.isEmpty() || !file.open(QIODevice::ReadOnly)
            || file.size() > maximumBytes) return {};
    const auto document = QJsonDocument::fromJson(file.readAll());
    const auto root = document.object();
    const auto savedAt = QDateTime::fromString(root["savedAt"].toString(), Qt::ISODateWithMs);
    if (root["version"].toInt() != version || root["fingerprint"].toString() != fingerprint
            || !savedAt.isValid() || savedAt > now || !root["apps"].isArray()) return {};
    for (const auto &value : root["apps"].toArray()) {
        const auto app = value.toObject();
        if (app["id"].toString().isEmpty() || app["name"].toString().isEmpty()) return {};
    }
    return {root["apps"].toArray().toVariantList(), savedAt, true};
}
inline bool write(const QString &path, const QString &fingerprint, const QVariantList &apps,
                  const QDateTime &savedAt = QDateTime::currentDateTimeUtc()) {
    if (path.isEmpty() || fingerprint.isEmpty() || !QDir().mkpath(QFileInfo(path).absolutePath())) return false;
    const auto data = QJsonDocument(QJsonObject{{"version", version}, {"fingerprint", fingerprint},
        {"savedAt", savedAt.toUTC().toString(Qt::ISODateWithMs)}, {"apps", QJsonArray::fromVariantList(apps)}})
        .toJson(QJsonDocument::Compact);
    if (data.size() > maximumBytes) return false;
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(data) == data.size() && file.commit();
}
}
