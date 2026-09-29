#include "../../src/transaction_status.h"
#include <cassert>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QLocale::setDefault(QLocale::English);
    const auto amount = downloadSizeText(1024);
    assert(simpleTransactionStatus("Downloading: 1 kB/2 MB (1 kB/s)", 1024, false)
           == "Downloading… " + amount + " received");
    assert(simpleTransactionStatus("Downloading files: 3/50 1 kB", 1024, false)
           == "Downloading… " + amount + " received");
    assert(simpleTransactionStatus("Downloading metadata: 5/(estimating) 1 kB", 0, false) == "Downloading…");
    assert(simpleTransactionStatus("Downloading extra data: 1 kB/2 MB", 1024, false)
           == "Downloading… " + amount + " received");
    // Accept localized templates without guessing from English text or percent.
    assert(simpleTransactionStatus("Herunterladen: 1 kB/2 MB", 0, false,
                                   {"Herunterladen: %s/%s"}) == "Downloading…");
    for (const auto raw : {"1 delta parts, 5 loose fetched; 2814 KiB transferred in 0 seconds",
                           "42 metadata, 100 content objects fetched", "", "Initializing",
                           "Unknown future diagnostic", "Téléchargement terminé: objets internes"})
        assert(simpleTransactionStatus(raw, 2814 * 1024, false) == "Installing…");
    assert(simpleTransactionStatus("Downloading: 1/2", 1024, true) == "Uninstalling…");
    assert(simpleTransactionStatus("Deleting deployment: technical details", 0, true) == "Uninstalling…");
    // Templates beginning with a placeholder must not match every status.
    assert(simpleTransactionStatus("internal diagnostics", 0, false, {"%s downloaded"}) == "Installing…");
    qInfo("PASS: simple download/install/removal labels, received bytes, localized formats and diagnostic suppression");
}
