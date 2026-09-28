#include "../../src/catalog_inputs.h"
#include "../../src/catalog_cache.h"
#include <QTemporaryDir>
#include <cassert>

int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    QTemporaryDir directory; assert(directory.isValid());
    const auto path = directory.filePath("cache/application-list.json");
    const auto now = QDateTime::fromString("2026-09-28T12:00:00.000Z", Qt::ISODateWithMs);
    const QVariantList apps{QVariantMap{{"id", "org.example.App"}, {"name", "Example"},
        {"developer", "Publisher"}, {"sources", QVariantList{QVariantMap{{"remote", "flathub"}}}}}};
    assert(!CatalogCache::read(path, "inputs", now).valid);
    assert(CatalogCache::write(path, "inputs", apps, now));
    const auto cached = CatalogCache::read(path, "inputs", now);
    assert(cached.valid && cached.apps == apps && cached.savedAt == now);
    assert(CatalogCache::fresh(now, now.addSecs(86399)));
    assert(!CatalogCache::fresh(now, now.addSecs(86400)));
    assert(!CatalogCache::fresh(now, now.addSecs(-1)));
    assert(!CatalogCache::read(path, "inputs", now.addSecs(-1)).valid);
    assert(!CatalogCache::read(path, "different-source", now).valid);
    assert(!CatalogCache::read(path, "", now).valid);
    const auto stale = CatalogCache::read(path, "inputs", now.addDays(2));
    assert(stale.valid && stale.apps == apps && !CatalogCache::fresh(stale.savedAt, now.addDays(2)));
    assert(CatalogCache::write(path, "inputs", {}, now));
    assert(CatalogCache::read(path, "inputs", now).valid); // A valid empty source is not corruption.
    assert(CatalogCache::write(path, "inputs", {QVariantMap{{"id", "missing-name"}}}, now));
    assert(!CatalogCache::read(path, "inputs", now).valid);
    QFile file(path); assert(file.open(QIODevice::WriteOnly)); file.write("{broken"); file.close();
    assert(!CatalogCache::read(path, "inputs", now).valid);
    assert(file.open(QIODevice::WriteOnly)); assert(file.resize(CatalogCache::maximumBytes + 1)); file.close();
    assert(!CatalogCache::read(path, "inputs", now).valid);
    assert(!CatalogCache::write(path + "/not-a-directory/list.json", "inputs", apps, now));

    // Same-size edits, active deployment changes and removals invalidate inputs.
    const auto xml = directory.filePath("appstream/snapshot-a/appstream.xml");
    assert(QDir().mkpath(QFileInfo(xml).absolutePath()));
    QFile metadata(xml); assert(metadata.open(QIODevice::WriteOnly)); metadata.write("one"); metadata.close();
    const auto before = CatalogInputs::contents(xml);
    assert(metadata.open(QIODevice::WriteOnly)); metadata.write("two"); metadata.close();
    assert(CatalogInputs::contents(xml) != before);
    assert(QFile::link("snapshot-a", directory.filePath("appstream/active")));
    QJsonArray first; CatalogInputs::catalogFiles(first, directory.filePath("appstream"));
    assert(first.size() == 2);
    assert(QDir().mkpath(directory.filePath("appstream/snapshot-b")));
    assert(QFile::copy(xml, directory.filePath("appstream/snapshot-b/appstream.xml")));
    assert(QFile::remove(directory.filePath("appstream/active")));
    assert(QFile::link("snapshot-b", directory.filePath("appstream/active")));
    QJsonArray second; CatalogInputs::catalogFiles(second, directory.filePath("appstream"));
    assert(first != second);
    assert(CatalogInputs::stamp(xml) != CatalogInputs::stamp(directory.filePath("missing")));
    qInfo("PASS: catalog cache round trip, 24-hour expiry, stale display, clock rollback, invalidation, corruption, oversize and unwritable paths");
}
