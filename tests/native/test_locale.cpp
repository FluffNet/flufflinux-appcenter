#include "rust_cache_fixture.h"
#include <QLocale>
#include <cassert>
int main(int argc, char **argv) {
    QCoreApplication app(argc,argv);
    QLocale::setDefault(QLocale::c());
    const auto date=QStringLiteral("2026-10-25T01:30:00.000Z");
    const auto formatted=fixture({{"operation","format"},{"bytes",1897850000},{"speed",2000000},{"date",date}});
    assert(formatted["size"]=="1.77 GiB" && formatted["speed"]=="1.91 MiB/s");
    assert(formatted["date"]==QLocale::system().toString(QDateTime::fromString(date,Qt::ISODateWithMs).toLocalTime(),QLocale::ShortFormat));
    for (const auto &pair : QList<QPair<double,QString>>{{0,"0.00 MiB"},{1073741824,"1.00 GiB"},{1000000000,"953.67 MiB"},{1072693248,"1023.00 MiB"}})
        assert(fixture({{"operation","format"},{"bytes",pair.first}})["size"]==pair.second);
    QLocale::setDefault(QLocale("de_DE"));
    const auto localized=fixture({{"operation","format"},{"bytes",1897850000},{"speed",1500000},{"date","invalid"}});
    assert(localized["size"]=="1,77 GiB" && localized["speed"]=="1,43 MiB/s" && localized["date"]=="");
    const auto progress=fixture({{"operation","stages"},{"phase","download"},{"operations",QJsonArray{QJsonObject{{"action","install"},{"downloadBytes",1897850000},{"receivedBytes",190740000},{"downloadProgress",0.1}}}}});
    assert(progress["downloadedSize"]=="181,90 MiB" && progress["downloadTotalSize"]=="1,77 GiB");
    qInfo("PASS: Rust values use native localized dates and consistent binary sizes/speeds");
}
