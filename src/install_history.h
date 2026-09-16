#pragma once
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QSaveFile>
#include <QStandardPaths>
#include <QDebug>
#include <utility>

// Observed successful installations, not guessed filesystem dates. Separate
// from Downloads, whose history only lasts for the current session.
class InstallHistory {
public:
    explicit InstallHistory(QString path = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                            + "/installation-dates.json") : m_path(std::move(path)) { reload(); }
    static QString key(const QString &scope, const QString &ref) { return scope + ":" + ref; }
    void reload() {
        QFile file(m_path);
        m_dates = file.open(QIODevice::ReadOnly)
            ? QJsonDocument::fromJson(file.readAll()).object().value("installations").toObject() : QJsonObject{};
    }
    QString date(const QString &scope, const QString &ref) const {
        const auto value = m_dates.value(key(scope, ref)).toString();
        return QDateTime::fromString(value, Qt::ISODateWithMs).isValid() ? value : QString{};
    }
    bool installed(const QString &scope, const QString &ref, const QDateTime &when = QDateTime::currentDateTimeUtc()) {
        if (!when.isValid()) return false;
        return save(scope, ref, when.toUTC().toString(Qt::ISODateWithMs));
    }
    bool removed(const QString &scope, const QString &ref) { return save(scope, ref, {}); }
private:
    bool save(const QString &scope, const QString &ref, const QString &date) {
        if (scope.isEmpty() || !ref.startsWith("app/") || ref.split('/').size() != 4) return false;
        if (!QDir().mkpath(QFileInfo(m_path).absolutePath())) return false;
        QLockFile lock(m_path + ".lock");
        if (!lock.tryLock(0)) { qWarning() << "Could not lock installation dates"; return false; }
        reload();
        auto next = m_dates;
        if (date.isEmpty()) next.remove(key(scope, ref));
        else next.insert(key(scope, ref), date);
        if (next == m_dates) return true;
        QSaveFile file(m_path);
        const auto data = QJsonDocument(QJsonObject{{"version", 1}, {"installations", next}}).toJson();
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
            qWarning() << "Could not save installation dates:" << file.errorString();
            return false;
        }
        m_dates = next;
        return true;
    }
    QString m_path;
    QJsonObject m_dates;
};
