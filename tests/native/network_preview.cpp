// Isolated NetworkManager responder for live UI captures. Never owns a name
// on the real system bus or changes the VM's network configuration.
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QVariantMap>
#include <cassert>
#include <iostream>

class Preview final : public QDBusVirtualObject {
public:
    uint state;
    QString introspect(const QString &) const override { return {}; }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &bus) override {
        if (message.interface() != "org.freedesktop.DBus.Properties" || message.member() != "GetAll") return false;
        bus.send(message.createReply(QVariantList{QVariantMap{{"State", state}, {"Connectivity", 1u}}}));
        return true;
    }
};
int main(int argc, char **argv) {
    QCoreApplication application(argc, argv);
    const auto address = qEnvironmentVariable("APPCENTER_PREVIEW_BUS");
    assert(!address.isEmpty() && argc == 2);
    auto bus = QDBusConnection::connectToBus(address, "preview-network-manager");
    Preview preview; preview.state = QByteArray(argv[1]).toUInt();
    assert(bus.registerService("org.freedesktop.NetworkManager"));
    assert(bus.registerVirtualObject("/org/freedesktop/NetworkManager", &preview));
    std::cout << "READY" << std::endl;
    return application.exec();
}
