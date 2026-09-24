#include "catalog_stats.h"
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QStandardPaths>
#include <cmath>

namespace {
constexpr qint64 responseLimit = 8 * 1024 * 1024;
bool validCount(const QJsonValue &value) {
    const auto n = value.toDouble(-1);
    return value.isDouble() && std::isfinite(n) && n >= 0 && n <= 1e12 && std::floor(n) == n;
}
bool validId(const QString &id) {
    static const QRegularExpression pattern("^[A-Za-z_][A-Za-z0-9_.-]{2,254}$");
    return pattern.match(id).hasMatch() && id.contains('.');
}
}

QJsonObject CatalogStats::validCounts(const QJsonObject &raw) {
    QJsonObject clean;
    for (auto it = raw.begin(); it != raw.end(); ++it)
        if (validId(it.key()) && validCount(it.value())) clean[it.key()] = it.value();
    return clean;
}

bool CatalogStats::readPage(const QByteArray &bytes, int page, int &totalPages, QJsonObject &counts) {
    if (bytes.size() > responseLimit) return false;
    const auto document = QJsonDocument::fromJson(bytes);
    if (!document.isObject()) return false;
    const auto object = document.object();
    const auto pages = object["totalPages"].toInt();
    if (object["page"].toInt() != page || pages < 1 || pages > 20 || page > pages
        || (totalPages && totalPages != pages) || object["hitsPerPage"].toInt() != 1000
        || !object["hits"].isArray() || object["hits"].toArray().size() > 1000) return false;
    totalPages = pages;
    for (const auto &value : object["hits"].toArray()) {
        const auto row = value.toObject();
        const auto id = row["app_id"].toString();
        if (validId(id) && validCount(row["installs_last_month"])) counts[id] = row["installs_last_month"];
    }
    return true;
}

QString CatalogStats::cachePath() const {
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/flathub-popularity.json";
}

CatalogStats::CatalogStats(QObject *parent) : QObject(parent), m_network(this) {
    QFile file(cachePath());
    if (!file.open(QIODevice::ReadOnly) || file.size() > 1024 * 1024) return;
    const auto saved = QJsonDocument::fromJson(file.readAll()).object();
    if (saved["version"].toInt() != 1) return;
    m_fetchedAt = QDateTime::fromString(saved["fetchedAt"].toString(), Qt::ISODate);
    if (!m_fetchedAt.isValid() || m_fetchedAt > QDateTime::currentDateTimeUtc()) return;
    m_counts = validCounts(saved["counts"].toObject());
    if (!m_counts.isEmpty()) m_state = "ready";
}

void CatalogStats::loadPopularity() {
    const auto now = QDateTime::currentDateTimeUtc();
    if (m_state == "loading" || (!m_counts.isEmpty() && m_fetchedAt.secsTo(now) < 24 * 3600)
        || (m_lastAttempt.isValid() && m_lastAttempt.secsTo(now) < 60)) return;
    m_lastAttempt = now; m_pending = {}; m_totalPages = 0;
    m_state = "loading"; emit changed(); fetchPage(1);
}

void CatalogStats::failed() {
    m_pending = {}; m_state = "unavailable"; emit changed();
}

void CatalogStats::fetchPage(int page) {
    // Public bulk listing: four requests for today's catalog, not one request
    // per installed app. Use Flathub's own 30-day install count, not a ranking
    // invented by App Center. TLS errors and redirects are never bypassed.
    QNetworkRequest request(QUrl(QString("https://flathub.org/api/v2/collection/popular?page=%1&per_page=1000").arg(page)));
    request.setHeader(QNetworkRequest::UserAgentHeader, "FluffLinux-AppCenter/2026.9");
    request.setRawHeader("Accept", "application/json");
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setTransferTimeout(15000);
    auto reply = m_network.get(request);
    connect(reply, &QNetworkReply::readyRead, this, [reply] {
        if (reply->bytesAvailable() > responseLimit) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, page] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError
            || reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() != 200
            || !readPage(reply->readAll(), page, m_totalPages, m_pending)) { failed(); return; }
        if (page < m_totalPages) { fetchPage(page + 1); return; }
        if (m_pending.isEmpty()) { failed(); return; }
        m_counts = m_pending; m_pending = {}; m_fetchedAt = QDateTime::currentDateTimeUtc();
        QDir().mkpath(QFileInfo(cachePath()).absolutePath());
        QSaveFile file(cachePath());
        if (file.open(QIODevice::WriteOnly)) {
            file.write(QJsonDocument(QJsonObject{{"version", 1}, {"fetchedAt", fetchedAt()},
                {"counts", m_counts}}).toJson(QJsonDocument::Compact));
            file.commit();
        }
        m_state = "ready"; emit changed();
    });
}
