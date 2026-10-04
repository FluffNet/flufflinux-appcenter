#pragma once
#include <QJsonDocument>
#include <QJsonObject>
// FFI transport only. Application state and decisions live in Rust.
extern "C" {
void *fluff_backend_new(const char *catalog);
char *fluff_backend_initial(void *manager);
char *fluff_backend_dispatch(void *manager, const char *request);
void fluff_backend_drop(void *manager);
void fluff_backend_string_free(char *value);
char *fluff_backend_utility(const char *request);
}
inline QJsonObject rustUtility(const QJsonObject &request) {
    const auto data = QJsonDocument(request).toJson(QJsonDocument::Compact);
    auto reply = fluff_backend_utility(data.constData());
    const auto result = QJsonDocument::fromJson(reply ? QByteArray(reply) : QByteArray()).object();
    fluff_backend_string_free(reply);
    return result;
}
