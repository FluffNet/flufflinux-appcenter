#include "../../src/network_status.h"
#include <QCoreApplication>
#include <QDBusVirtualObject>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QTimer>
#include <QTest>
#include <cassert>
#include <functional>
#include <iostream>

namespace {
const QString service = "org.freedesktop.NetworkManager";
const QString path = "/org/freedesktop/NetworkManager";
void until(const std::function<bool()> &done) {
    QElapsedTimer timer; timer.start();
    while (!done() && timer.elapsed() < 4000) QTest::qWait(10);
    assert(done());
}
class FakeNM final : public QDBusVirtualObject {
public:
    QVariantMap properties{{"State", 70u}, {"Connectivity", 4u}};
    bool error = false;
    bool delay = false;
    bool drop = false;
    int reads = 0;
    QString introspect(const QString &) const override { return {}; }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &bus) override {
        if (message.interface() != "org.freedesktop.DBus.Properties" || message.member() != "GetAll") {
            assert(false && "Network observer must only read properties"); return false;
        }
        assert(message.arguments() == QVariantList{service});
        ++reads;
        if (drop) return true; // Exercise the observer's bounded call timeout.
        auto reply = error ? message.createErrorReply("org.freedesktop.DBus.Error.Failed", "fixture error")
                           : message.createReply(QVariantList{properties});
        if (delay) { delay = false; QTimer::singleShot(200, this, [bus, reply] { bus.send(reply); }); }
        else bus.send(reply);
        return true;
    }
    void change(const QDBusConnection &bus, uint state, uint connectivity) {
        properties = {{"State", state}, {"Connectivity", connectivity}};
        auto signal = QDBusMessage::createSignal(path, "org.freedesktop.DBus.Properties", "PropertiesChanged");
        signal << service << QVariantMap{} << QStringList{"State", "Connectivity"};
        assert(bus.send(signal));
    }
};
}

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (app.arguments().contains("--system")) {
        NetworkStatus live; until([&] { return live.ready(); });
        std::cout << "NetworkManager state: " << live.state().toStdString() << '\n';
        return 0;
    }
    assert(NetworkStatus::classify({}) == "unknown");
    assert(NetworkStatus::classify({{"State", "invalid"}}) == "unknown");
    for (uint state : {0u, 999u}) assert(NetworkStatus::classify({{"State", state}}) == "unknown");
    for (uint state : {10u, 20u})
        assert(NetworkStatus::classify({{"State", state}, {"Devices", QStringList{}}, {"Connectivity", 1u}}) == "offline");
    for (uint state : {30u, 40u}) assert(NetworkStatus::classify({{"State", state}}) == "connecting");
    for (uint connectivity : {0u, 1u, 2u, 3u, 4u})
        assert(NetworkStatus::classify({{"State", 50u}, {"Connectivity", connectivity}}) == "local");
    assert(NetworkStatus::classify({{"State", 60u}, {"Connectivity", 1u}}) == "limited");
    assert(NetworkStatus::classify({{"State", 60u}, {"Connectivity", 2u}}) == "portal");
    assert(NetworkStatus::classify({{"State", 70u}, {"Connectivity", 0u}}) == "online");
    assert(NetworkStatus::classify({{"State", 70u}, {"Connectivity", 3u}}) == "limited");
    assert(NetworkStatus::classify({{"State", 70u}, {"Connectivity", 4u}}) == "online");

    // The script runs this on a private session bus, never the real system bus.
    auto bus = QDBusConnection::sessionBus();
    FakeNM fake;
    assert(bus.registerService(service));
    assert(bus.registerVirtualObject(path, &fake));
    const auto client = QDBusConnection::connectToBus(QDBusConnection::SessionBus, "network-observer-test");
    NetworkStatus observed(nullptr, client);
    until([&] { return observed.ready(); }); assert(observed.state() == "online");
    const QList<QPair<uint, QString>> cases{{20, "offline"}, {50, "local"}, {60, "limited"},
        {40, "connecting"}, {0, "unknown"}, {70, "online"}};
    for (const auto &item : cases) {
        fake.change(bus, item.first, 1);
        until([&] { return observed.state() == item.second; });
    }
    fake.change(bus, 60, 2); until([&] { return observed.state() == "portal"; });
    fake.change(bus, 20, 1); until([&] { return observed.state() == "offline"; });
    fake.error = true;
    fake.change(bus, 20, 1); until([&] { return observed.state() == "unknown"; });
    fake.error = false;
    fake.delay = true;
    const auto oldReads = fake.reads;
    fake.change(bus, 20, 1); until([&] { return fake.reads > oldReads; });
    fake.change(bus, 50, 1); until([&] { return observed.state() == "local"; });
    QTest::qWait(300); assert(observed.state() == "local"); // Stale offline reply ignored.
    fake.drop = true;
    fake.change(bus, 20, 1); until([&] { return observed.state() == "unknown"; });
    fake.drop = false;
    fake.change(bus, 20, 1); until([&] { return observed.state() == "offline"; });
    assert(bus.unregisterService(service));
    until([&] { return observed.state() == "unknown"; });
    fake.properties = {{"State", 70u}, {"Connectivity", 4u}};
    assert(bus.registerService(service));
    until([&] { return observed.state() == "online"; });
    std::cout << "PASS: NM states, LAN/limited/portal allowed, live property changes, errors/timeouts, stale replies, daemon restart; read-only\n";
}
