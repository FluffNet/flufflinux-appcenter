#include "../../src/install_history.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <cassert>
#include <cstdio>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QTemporaryDir directory;
    assert(directory.isValid());
    const auto path = directory.path() + "/data/dates.json";
    const QString ref = "app/org.example.App/x86_64/stable";
    const QString other = "app/org.example.Other/x86_64/stable";
    const auto first = QDateTime::fromString("2026-09-16T20:00:00.000Z", Qt::ISODateWithMs);
    const auto second = first.addDays(1);
    InstallHistory dates(path), separateInstance(path);
    assert(dates.date("user", ref).isEmpty()); // No backfilled dates.
    assert(dates.installed("user", ref, first));
    InstallHistory restarted(path);
    assert(restarted.date("user", ref) == first.toString(Qt::ISODateWithMs));
    assert(restarted.date("system", ref).isEmpty());
    assert(restarted.date("user", "app/org.example.App/aarch64/stable").isEmpty());
    assert(restarted.date("user", "app/org.example.App/x86_64/beta").isEmpty());
    assert(separateInstance.installed("user", other, first));
    dates.reload();
    assert(!dates.date("user", ref).isEmpty() && !dates.date("user", other).isEmpty());
    assert(dates.removed("user", ref));
    restarted.reload();
    assert(restarted.date("user", ref).isEmpty());
    assert(!restarted.date("user", other).isEmpty());
    assert(dates.installed("user", ref, second));
    restarted.reload();
    assert(restarted.date("user", ref) == second.toString(Qt::ISODateWithMs));
    assert(!dates.installed("user", ref, QDateTime{}));
    assert(!dates.installed("user", "runtime/org.example.Platform/x86_64/1", first));
    QFile invalid(directory.path() + "/invalid.json");
    assert(invalid.open(QIODevice::WriteOnly));
    invalid.write("{\"installations\":{\"user:app/org.example.App/x86_64/stable\":\"not a date\"}}");
    invalid.close();
    assert(InstallHistory(invalid.fileName()).date("user", ref).isEmpty());
    assert(!InstallHistory(invalid.fileName() + "/impossible.json").installed("user", ref));
    assert(InstallHistory::displayDate("not a date").isEmpty());
    for (const auto &localeName : {"en_US", "en_GB", "de_DE", "pl_PL", "he_IL", "ar_EG"}) {
        const QLocale locale(localeName);
        for (const auto &zoneName : {"Europe/Warsaw", "America/New_York", "Asia/Tokyo"}) {
            const QTimeZone zone(zoneName);
            assert(zone.isValid());
            // Include a daylight-saving boundary as well as a date rollover.
            for (const auto &utc : {first, QDateTime::fromString("2026-10-25T01:30:00.000Z", Qt::ISODateWithMs)}) {
                const auto local = utc.toTimeZone(zone);
                const auto displayed = InstallHistory::displayDate(utc.toString(Qt::ISODateWithMs), locale, zone);
                assert(displayed == locale.toString(local, QLocale::ShortFormat));
                assert(displayed.contains(locale.toString(local.time(), QLocale::ShortFormat)));
                assert(!displayed.contains(locale.dayName(local.date().dayOfWeek(), QLocale::LongFormat)));
            }
        }
    }
    // Check Qt's supported locale patterns, not just the machine's locale.
    for (const auto &locale : QLocale::matchingLocales(QLocale::AnyLanguage, QLocale::AnyScript, QLocale::AnyTerritory))
        assert(!locale.dateTimeFormat(QLocale::ShortFormat).contains("ddd"));
    assert(InstallHistory::displayDate(first.toString(Qt::ISODateWithMs))
           == QLocale::system().toString(first.toTimeZone(QTimeZone::systemTimeZone()), QLocale::ShortFormat));
    puts("PASS: dates persist, missing dates stay absent, scopes/refs isolated, removal clears date, reinstall records a new date");
    puts("PASS: localized installation date/time, system timezone, DST/date rollover, no weekday in supported short formats");
}
