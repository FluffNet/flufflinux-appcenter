#include "../../src/transaction_progress.h"
#include <QCoreApplication>
#include <cassert>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QVariantMap runtime{{"action", "install"}, {"downloadBytes", 300}, {"phase", "download"},
                        {"downloadProgress", 0.5}, {"receivedBytes", 100}};
    QVariantMap application{{"action", "install"}, {"downloadBytes", 100}, {"phase", "waiting"}};
    auto result = transactionStages({runtime, application}, "download");
    assert(result["downloadProgress"].toDouble() == 0.375);
    assert(result["installCompleted"].toInt() == 0 && result["installTotal"].toInt() == 2);
    runtime["phase"] = "install"; runtime["downloadProgress"] = 1;
    result = transactionStages({runtime, application}, "install");
    assert(result["downloadProgress"].toDouble() == 0.75);
    assert(result["installProgress"].toDouble() == 0); // Pull != installation.
    runtime["phase"] = "complete";
    application["phase"] = "download"; application["downloadProgress"] = 0.5;
    application["estimating"] = true;
    result = transactionStages({runtime, application}, "download");
    assert(result["downloadProgress"].toDouble() == 0.875 && result["downloadEstimating"].toBool());
    assert(result["installProgress"].toDouble() == 0.5);
    application["phase"] = "install"; application["downloadProgress"] = 1;
    result = transactionStages({runtime, application}, "install");
    assert(result["downloadProgress"].toDouble() == 1);
    assert(result["installCompleted"].toInt() == 1); // Even when ALL downloads finish.
    application["phase"] = "failed";
    assert(transactionStages({runtime, application}, "failed")["installCompleted"].toInt() == 1);
    application["phase"] = "complete";
    assert(transactionStages({runtime, application}, "complete")["installProgress"].toDouble() == 1);
    application["action"] = "install-bundle";
    assert(!transactionStages({application}, "install")["hasDownload"].toBool());
    application["phase"] = "waiting"; application["action"] = "install"; application["downloadBytes"] = 0;
    application["downloadProgress"] = 0;
    runtime["downloadBytes"] = 1e12;
    assert(transactionStages({runtime, application}, "preparing")["downloadProgress"].toDouble() <= 0.99);
    const QVariantMap removal{{"action", "uninstall"}, {"phase", "complete"}};
    assert(transactionStages({runtime, removal}, "complete")["installTotal"].toInt() == 1);
    qInfo("PASS: independent download/deployment progress, interleaved dependencies, estimating, failures, local bundles and completion");
}
