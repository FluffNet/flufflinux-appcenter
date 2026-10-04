#include "flatpak_manager.h"
#include "rust_backend.h"
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPointer>
#include <QProcess>
#include <QPixmapCache>
#include <QSet>

struct FlatpakManager::Process {
    QPointer<QProcess> process;
    QPointer<QTimer> timeout;
    QString role, error;
    quint64 serial = 0;
    qint64 limit = 0;
    QByteArray output, lineBuffer, diagnostics, diagnosticLines;
    bool stream = false, stderrLines = false, terminal = false, timedOut = false;
};

FlatpakManager::FlatpakManager(const QVariantList &catalog, QObject *parent) : QObject(parent) {
    const auto input = QJsonDocument::fromVariant(catalog).toJson(QJsonDocument::Compact);
    m_backend = fluff_backend_new(input.constData());
    if (!m_backend) qFatal("Could not initialize the Rust backend");
    apply(fluff_backend_initial(m_backend));
    QDBusConnection::sessionBus().connect({}, "/KIconLoader", "org.kde.KIconLoader",
        "iconChanged", this, SLOT(refreshThemeIcons(int)));
}
FlatpakManager::~FlatpakManager() {
    dispatch("shutdown");
    m_stopping = true;
    for (auto timer : m_timers) timer->stop();
    const auto processes = m_processes;
    for (const auto &state : processes) {
        if (!state->process) continue;
        state->process->disconnect(this);
        state->process->closeWriteChannel();
        if (!state->process->waitForFinished(250)) {
            state->process->kill();
            state->process->waitForFinished(1000);
        }
    }
    m_processes.clear();
    fluff_backend_drop(m_backend);
}
QVariant FlatpakManager::dispatch(const QString &action, const QVariantList &arguments) {
    if (m_stopping) return {};
    const auto request = QJsonDocument(QJsonObject{{"action", action}, {"args", QJsonArray::fromVariantList(arguments)}}).toJson(QJsonDocument::Compact);
    return apply(fluff_backend_dispatch(m_backend, request.constData()));
}
QVariant FlatpakManager::apply(char *reply) {
    const auto response = QJsonDocument::fromJson(reply ? QByteArray(reply) : QByteArray()).object();
    fluff_backend_string_free(reply);
    // QML can synchronously request another action from a property signal.
    // Preserve Rust's envelope order so a cancel cannot overtake its start.
    m_responses.enqueue(response);
    if (!m_applying) {
        m_applying = true;
        while (!m_responses.isEmpty()) applyResponse(m_responses.dequeue());
        m_applying = false;
    }
    return response["return"].toVariant();
}
void FlatpakManager::applyResponse(const QJsonObject &response) {
    const auto changes = response["state"].toObject();
    for (auto it = changes.begin(); it != changes.end(); ++it) m_state[it.key()] = it.value().toVariant();
    QSet<QByteArray> notifications;
    if (changes.contains("popularity")) notifications.insert("popularityChanged");
    if (changes.contains("jobs") || changes.contains("busy") || changes.contains("sourceInputStatus") || changes.contains("backgroundWorkPending")) notifications.insert("jobsChanged");
    if (changes.contains("review")) notifications.insert("reviewChanged");
    if (changes.contains("installedApps") || changes.contains("installedLoading") || changes.contains("installedError") || changes.contains("iconRevision")) notifications.insert("installedChanged");
    if (changes.contains("installSizes")) notifications.insert("installSizesChanged");
    if (changes.contains("appPermissions")) notifications.insert("appPermissionsChanged");
    if (changes.contains("appAddons")) notifications.insert("appAddonsChanged");
    if (changes.contains("updates")) notifications.insert("updatesChanged");
    if (changes.contains("catalog") || changes.contains("catalogLoading") || changes.contains("catalogSourcesUnavailable")) notifications.insert("catalogChanged");
    if (changes.contains("catalogProgress")) notifications.insert("catalogProgressChanged");
    if (changes.contains("repositories") || changes.contains("sourcesBusy") || changes.contains("sourcesError")) notifications.insert("repositoriesChanged");
    for (const auto &name : notifications) QMetaObject::invokeMethod(this, name.constData(), Qt::DirectConnection);
    for (const auto &value : response["signals"].toArray()) {
        const auto signal = value.toObject();
        const auto args = signal["args"].toArray();
        if (signal["name"] == "appOpened") emit appOpened(args.at(0).toObject().toVariantMap());
        else if (signal["name"] == "homeRequested") emit homeRequested();
        else if (signal["name"] == "inputError") emit inputError(args.at(0).toString());
    }
    for (const auto &command : response["commands"].toArray()) execute(command.toObject());
}
void FlatpakManager::processEvent(const std::shared_ptr<Process> &state, QJsonObject message) {
    if (m_stopping) return;
    message["serial"] = double(state->serial); message["role"] = state->role;
    dispatch("event", {message.toVariantMap()});
}
void FlatpakManager::readOutput(const std::shared_ptr<Process> &state, bool diagnostics) {
    if (!state->process || state->terminal) return;
    if (diagnostics) {
        const auto bytes = state->process->readAllStandardError();
        state->diagnostics = (state->diagnostics + bytes).right(8192);
        if (!state->stderrLines) return;
        state->diagnosticLines += bytes;
        while (state->diagnosticLines.contains('\n')) {
            const auto end = state->diagnosticLines.indexOf('\n');
            const auto line = state->diagnosticLines.left(end);
            state->diagnosticLines.remove(0, end + 1);
            if (line.size() <= 4096) processEvent(state, {{"kind", "line"}, {"line", QString::fromUtf8(line)}});
        }
        if (state->diagnosticLines.size() > 4096) state->diagnosticLines.clear();
        return;
    }
    const auto bytes = state->process->readAllStandardOutput();
    auto &buffer = state->stream ? state->lineBuffer : state->output;
    buffer += bytes;
    if (buffer.size() > state->limit) {
        state->error = "Worker response exceeded its size limit";
        state->process->kill(); return;
    }
    if (!state->stream) return;
    while (buffer.contains('\n')) {
        const auto end = buffer.indexOf('\n');
        const auto line = buffer.left(end); buffer.remove(0, end + 1);
        processEvent(state, {{"kind", "line"}, {"line", QString::fromUtf8(line)}});
        if (state->terminal) return;
    }
}
void FlatpakManager::finish(const std::shared_ptr<Process> &state, int code, bool crashed) {
    if (state->terminal) return;
    readOutput(state, false); readOutput(state, true);
    state->terminal = true;
    if (state->timeout) { state->timeout->stop(); state->timeout->setObjectName({}); }
    m_processes.remove(state->serial);
    processEvent(state, {{"kind", "finished"}, {"code", code}, {"crashed", crashed},
        {"stdout", QString::fromUtf8(state->output)}, {"stderr", QString::fromUtf8(state->diagnostics)},
        {"error", state->error}, {"timedOut", state->timedOut}});
    if (state->process) state->process->deleteLater();
}
void FlatpakManager::execute(const QJsonObject &command) {
    const auto kind = command["command"].toString();
    if (kind == "background") { emit backgroundCommand(command["data"].toObject().toVariantMap()); return; }
    if (kind == "defer") {
        const auto action = command["action"].toString();
        QTimer::singleShot(0, this, [this, action] { dispatch(action); });
    } else if (kind == "timer") {
        const auto action = command["action"].toString();
        auto timer = m_timers.value(action);
        if (!timer) {
            timer = new QTimer(this); m_timers[action] = timer;
            connect(timer, &QTimer::timeout, this, [this, action] { dispatch(action); });
        }
        const int interval = command["interval"].toInt();
        if (interval > 0) timer->start(interval); else timer->stop();
    } else if (kind == "start") {
        auto state = std::make_shared<Process>();
        state->serial = command["serial"].toDouble(); state->role = command["role"].toString();
        state->limit = command["limit"].toDouble(); state->stream = command["stream"].toBool();
        state->stderrLines = command["stderrLines"].toBool();
        auto process = new QProcess(this); state->process = process;
        auto timer = new QTimer(process); state->timeout = timer; timer->setSingleShot(true);
        timer->setObjectName(state->role + "WorkTimeout");
        m_processes.insert(state->serial, state);
        connect(process, &QProcess::readyReadStandardOutput, this, [this, state] { readOutput(state, false); });
        connect(process, &QProcess::readyReadStandardError, this, [this, state] { readOutput(state, true); });
        connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this, state](int code, QProcess::ExitStatus status) { finish(state, code, status != QProcess::NormalExit); });
        connect(process, &QProcess::errorOccurred, this, [this, state](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                state->error = state->process->errorString(); finish(state, -1, true);
            }
        });
        connect(timer, &QTimer::timeout, this, [state] {
            state->timedOut = true; state->error = "Worker timed out";
            if (state->process) state->process->kill();
        });
        QStringList args;
        for (const auto &arg : command["args"].toArray()) args.append(arg.toString());
        auto program = command["program"].toString();
        if (program == "@self") program = QCoreApplication::applicationFilePath();
        process->start(program, args);
        if (!command["interactive"].toBool()) process->closeWriteChannel();
        const int timeout = command["timeout"].toInt();
        if (timeout > 0) timer->start(timeout);
    } else if (kind == "launch") {
        QStringList args;
        for (const auto &arg : command["args"].toArray()) args.append(arg.toString());
        if (!QProcess::startDetached(command["program"].toString(), args)) emit inputError(tr("Could not start this app."));
    } else if (kind == "refreshIcons") {
        auto message = QDBusMessage::createSignal("/KIconLoader", "org.kde.KIconLoader", "iconChanged");
        message << 0;
        if (!QDBusConnection::sessionBus().send(message)) refreshThemeIcons(0);
    } else {
        const auto state = m_processes.value(quint64(command["serial"].toDouble()));
        if (!state || state->role != command["role"].toString() || state->terminal || !state->process) return;
        if (kind == "write") state->process->write(command["data"].toString().toUtf8());
        else if (kind == "close") state->process->closeWriteChannel();
        else if (kind == "kill") state->process->kill();
        else if (kind == "deadline") {
            const int timeout = command["timeout"].toInt();
            if (timeout > 0) state->timeout->start(timeout); else state->timeout->stop();
        }
    }
}
void FlatpakManager::refreshThemeIcons(int) {
    QTimer::singleShot(0, this, [this] {
        if (m_stopping) return;
        QPixmapCache::clear();
        dispatch("iconsChanged");
    });
}
