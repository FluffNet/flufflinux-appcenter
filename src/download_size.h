#pragma once
#include <QLocale>

// App estimates, dependency sizes, and live transfer totals must use the same
// units. Mixing binary GiB with decimal GB makes identical byte counts appear
// different (1,897,850,000 bytes is both 1.77 GiB and 1.90 GB).
inline QString downloadSizeText(quint64 bytes) {
    const bool gigabytes = bytes >= 1000000000;
    return QLocale().toString(double(bytes) / (gigabytes ? 1000000000 : 1000000), 'f', 2)
        + (gigabytes ? " GB" : " MB");
}
