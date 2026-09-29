#include "flatpak_addons.h"
#include <QJsonDocument>
#include <iostream>
#include <unistd.h>

extern "C" int fluff_addons_worker(const char *json) {
    int argc = 1;
    char name[] = "flufflinux-appcenter-addons";
    char *argv[] = {name, nullptr};
    QCoreApplication app(argc, argv);
    const auto result = geteuid() == 0 ? AppAddons::error("Run App Center as your desktop user.")
        : AppAddons::read(QJsonDocument::fromJson(QByteArray(json)).object());
    std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << std::endl;
    return 0;
}
