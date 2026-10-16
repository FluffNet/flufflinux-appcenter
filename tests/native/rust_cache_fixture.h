#pragma once
// Test-only marshaling. All cache decisions and IO are the production Rust code.
#include "../../src/rust_backend.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
extern "C" char *fluff_backend_fixture(const char *request);
inline QJsonObject fixture(const QJsonObject &request) {
    const auto data = QJsonDocument(request).toJson(QJsonDocument::Compact);
    auto reply = fluff_backend_fixture(data.constData());
    const auto result = QJsonDocument::fromJson(reply ? QByteArray(reply) : QByteArray()).object();
    fluff_backend_string_free(reply);
    return result;
}
namespace CatalogInputs {
inline QString fingerprint() { return fixture({{"operation", "fingerprint"}})["value"].toString(); }
}
namespace CatalogCache {
struct Cached { bool valid; QVariantList apps; QDateTime savedAt; };
inline Cached read(const QString &path, const QString &fingerprint) {
    const auto value = fixture({{"operation", "read"}, {"path", path}, {"fingerprint", fingerprint}});
    return {value["valid"].toBool(), value["apps"].toArray().toVariantList(), QDateTime::fromString(value["savedAt"].toString(), Qt::ISODateWithMs)};
}
inline bool write(const QString &path, const QString &fingerprint, const QVariantList &apps, const QDateTime &date) {
    return fixture({{"operation", "write"}, {"path", path}, {"fingerprint", fingerprint},
        {"apps", QJsonArray::fromVariantList(apps)}, {"date", date.toString(Qt::ISODateWithMs)}})["ok"].toBool();
}
inline bool fresh(const QDateTime &date) { return date.isValid() && fixture({{"operation", "fresh"}, {"date", date.toString(Qt::ISODateWithMs)}})["value"].toBool(); }
inline QJsonObject snapshot(const QJsonObject &request, const QVariantList &apps, const QString &) {
    return fixture({{"operation", "snapshot"}, {"request", request}, {"apps", QJsonArray::fromVariantList(apps)}});
}
}
