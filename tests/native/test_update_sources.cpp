#include "../../src/update_sources.h"
#include <cassert>
#include <cstdio>
int main() {
    const QString stable = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    const QString beta = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    const QJsonObject user{{"scope", "user"}, {"name", "flathub"},
        {"url", "https://dl.flathub.org/repo/"}, {"enabled", true}, {"verified", true}, {"sourceKey", "same-policy"}};
    auto definition = [&](QString scope, QString origin, QJsonArray sources) {
        return UpdateSources::restorationDefinition(scope, origin, sources);
    };
    assert(definition("system", "flathub", {user}) == stable);
    assert(definition("extra", "flathub", {user}) == stable);
    assert(definition("user", "flathub", {user}).isEmpty());
    assert(definition("system", "flathub", {}).isEmpty());
    assert(definition("system", "custom", {user}).isEmpty());
    assert(definition("system", "flathub-beta", {user}).isEmpty());
    for (const auto &option : {"enabled", "verified"}) {
        auto invalid = user; invalid[option] = false;
        assert(definition("system", "flathub", {invalid}).isEmpty());
    }
    for (const auto &url : {"https://evil.example/repo/", "http://dl.flathub.org/repo/",
             "https://dl.flathub.org/beta-repo/", "https://dl.flathub.org/repo/?x=1"}) {
        auto invalid = user; invalid["url"] = url;
        assert(definition("system", "flathub", {invalid}).isEmpty());
    }
    auto system = user; system["scope"] = "default"; system["enabled"] = false;
    assert(definition("system", "flathub", {user, system}).isEmpty());
    system["url"] = "https://different.example/repo";
    assert(definition("system", "flathub", {user, system}).isEmpty());
    auto betaUser = user; betaUser["name"] = "flathub-beta"; betaUser["url"] = "https://dl.flathub.org/beta-repo/";
    assert(definition("system", "flathub-beta", {betaUser}) == beta);
    assert(UpdateSources::restoreArguments("system", "flathub", stable)
        == QStringList({"--system", "remote-add", "--if-not-exists", "--from", "flathub", stable}));
    assert(UpdateSources::restoreArguments("extra", "flathub", stable).first() == "--installation=extra");
    system = user; system["scope"] = "default";
    const auto merged = Sources::group({user, system});
    assert(merged.size() == 1 && merged[0].toObject()["scope"] == "merged");
    assert(merged[0].toObject()["hasUser"].toBool() && merged[0].toObject()["hasSystem"].toBool());
    system["sourceKey"] = "different-signing-policy";
    assert(Sources::group({user, system}).size() == 2);
    puts("PASS: official user-to-system restoration policy, scopes, no overwrite/re-enable, grouped identity");
}
