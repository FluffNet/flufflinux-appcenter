#include "../../src/catalog_stats.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonArray>
#include <QTemporaryDir>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <cassert>
#include <iostream>

int main(int argc, char **argv) {
    QTemporaryDir root;
    qputenv("XDG_CACHE_HOME", root.path().toUtf8());
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName("catalog-test");
    auto clean = CatalogStats::validCounts({{"org.example.Zero", 0}, {"org.example.Good", 123},
        {"org.example.Negative", -1}, {"org.example.Float", 1.5}, {"org.example.Null", QJsonValue()},
        {"org.example.String", "10"}, {"../../bad", 10}});
    assert(clean.size() == 2 && clean["org.example.Zero"] == 0);
    auto page = [](int index, int pages, QJsonArray hits) {
        return QJsonDocument(QJsonObject{{"page", index}, {"totalPages", pages},
            {"hitsPerPage", 1000}, {"hits", hits}}).toJson();
    };
    QJsonObject counts; int total = 0;
    assert(CatalogStats::readPage(page(1, 2, {QJsonObject{{"app_id", "org.example.One"}, {"installs_last_month", 12}}}), 1, total, counts));
    assert(total == 2 && counts["org.example.One"] == 12);
    assert(CatalogStats::readPage(page(2, 2, {QJsonObject{{"app_id", "org.telegram.desktop"}, {"installs_last_month", 0}}}), 2, total, counts));
    assert(counts["org.telegram.desktop"] == 0);
    assert(!CatalogStats::readPage(page(2, 3, {}), 2, total, counts)); // Inconsistent pagination.
    assert(!CatalogStats::readPage(page(1, 2, {}), 2, total, counts)); // Repeated/wrong page.
    assert(!CatalogStats::readPage("<html>offline</html>", 1, total, counts));
    assert(!CatalogStats::readPage(QByteArray(8 * 1024 * 1024 + 1, ' '), 1, total, counts));
    assert(!CatalogStats::readPage(page(1, 999, {}), 1, total, counts));
    CatalogStats empty;
    assert(empty.state() == "idle" && empty.counts().isEmpty()); // No automatic network call.
    const auto path = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(path); QFile file(path + "/flathub-popularity.json");
    assert(file.open(QIODevice::WriteOnly));
    file.write(QJsonDocument(QJsonObject{{"version", 1}, {"fetchedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {"counts", counts}}).toJson()); file.close();
    CatalogStats cached;
    assert(cached.state() == "ready" && cached.counts().size() == 2);
    cached.loadPopularity();
    assert(cached.state() == "ready"); // Fresh cache does not issue a request.
    std::cout << "PASS: counts, zero vs missing, pagination, bounded responses, cache, no startup network\n";
}
