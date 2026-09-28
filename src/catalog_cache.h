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
#include <QCryptographicHash>

namespace CatalogCache {
// Version 3 adds integrity checking; old snapshots are never trusted as v3.
constexpr int version = 3;
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
inline QString checksum(QJsonObject object) {
    object.remove("checksum");
    return QString::fromLatin1(QCryptographicHash::hash(QJsonDocument(object).toJson(QJsonDocument::Compact),
        QCryptographicHash::Sha256).toHex());
}
inline Entry read(const QString &path, const QString &fingerprint,
                  const QDateTime &now = QDateTime::currentDateTimeUtc()) {
    QFile file(path);
    if (path.isEmpty() || fingerprint.isEmpty() || !QFileInfo(path).isFile() || !file.open(QIODevice::ReadOnly)
            || file.size() > maximumBytes) return {};
    const auto data = file.read(maximumBytes + 1);
    if (data.size() > maximumBytes) return {};
    const auto document = QJsonDocument::fromJson(data);
    const auto root = document.object();
    const auto savedAt = QDateTime::fromString(root["savedAt"].toString(), Qt::ISODateWithMs);
    if (root["version"].toInt() != version || root["fingerprint"].toString() != fingerprint
            || root["checksum"].toString() != checksum(root)
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
    QJsonObject object{{"version", version}, {"fingerprint", fingerprint},
        {"savedAt", savedAt.toUTC().toString(Qt::ISODateWithMs)}, {"apps", QJsonArray::fromVariantList(apps)}};
    object["checksum"] = checksum(object);
    const auto data = QJsonDocument(object).toJson(QJsonDocument::Compact);
    if (data.size() > maximumBytes) return false;
    QSaveFile file(path);
    file.setDirectWriteFallback(false); // Never truncate the previous good cache.
    return file.open(QIODevice::WriteOnly) && file.write(data) == data.size() && file.commit();
}
inline QJsonObject snapshot(const QJsonObject &request, const QVariantList &apps, const QString &fingerprint) {
    const auto savedAt = request["resetAge"].toBool() ? QDateTime::currentDateTimeUtc()
        : QDateTime::fromString(request["savedAt"].toString(), Qt::ISODateWithMs);
    const bool stable = !fingerprint.isEmpty() && fingerprint == request["fingerprint"].toString();
    const bool saved = stable && fresh(savedAt) && write(request["path"].toString(), fingerprint, apps, savedAt);
    if (stable && fresh(savedAt) && !saved) qWarning("Could not save application-list cache; browsing remains available");
    return {{"apps", QJsonArray::fromVariantList(apps)}, {"savedAt", savedAt.toUTC().toString(Qt::ISODateWithMs)},
        {"cacheSaved", saved}};
}
}
