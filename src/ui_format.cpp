// Native locale presentation only. Rust owns values, units and stored dates.
#include <QDateTime>
#include <QLocale>
#include <cstdlib>
#include <cstring>

static char *copy(const QString &value) {
    const auto bytes = value.toUtf8();
    auto result = static_cast<char *>(std::malloc(bytes.size() + 1));
    if (result) std::memcpy(result, bytes.constData(), bytes.size() + 1);
    return result;
}
extern "C" char *fluff_ui_number(double value) {
    return copy(QLocale().toString(value, 'f', 2));
}
extern "C" char *fluff_ui_date(const char *value) {
    const auto date = QDateTime::fromString(QString::fromUtf8(value), Qt::ISODateWithMs);
    return copy(date.isValid() ? QLocale::system().toString(date.toLocalTime(), QLocale::ShortFormat) : QString());
}
