#include "../../src/transaction_progress.h"
#include <QCoreApplication>
#include <cassert>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QLocale::setDefault(QLocale::c());
    QVariantMap runtime{{"action", "install"}, {"downloadBytes", 300}, {"phase", "download"},
                        {"downloadProgress", 0.5}, {"receivedBytes", 100}};
    QVariantMap application{{"action", "install"}, {"downloadBytes", 100}, {"phase", "waiting"}};
    auto result = transactionStages({runtime, application}, "download");
    assert(result["downloadProgress"].toDouble() == 0.375);
    assert(qAbs(result["progress"].toDouble() - 0.3375) < 1e-9);
    assert(result["receivedBytes"].toULongLong() == 100);
    assert(result["downloadTotalBytes"].toULongLong() == 400);
    assert(result["installCompleted"].toInt() == 0 && result["installTotal"].toInt() == 2);
    runtime["phase"] = "install"; runtime["downloadProgress"] = 1; runtime["receivedBytes"] = 200;
    result = transactionStages({runtime, application}, "install");
    assert(result["downloadProgress"].toDouble() == 0.75);
    assert(result["installProgress"].toDouble() == 0); // Pull != installation.
    assert(result["downloadTotalBytes"].toULongLong() == 300); // Actual runtime + pending app estimate.
    runtime["phase"] = "complete";
    application["phase"] = "download"; application["downloadProgress"] = 0.5;
    application["estimating"] = true;
    result = transactionStages({runtime, application}, "download");
    assert(result["downloadProgress"].toDouble() == 0.875 && result["downloadEstimating"].toBool());
    assert(result["installProgress"].toDouble() == 0.5);
    application["phase"] = "install"; application["downloadProgress"] = 1;
    application["receivedBytes"] = 80;
    result = transactionStages({runtime, application}, "install");
    assert(result["downloadProgress"].toDouble() == 1);
    assert(result["installCompleted"].toInt() == 1); // Even when ALL downloads finish.
    assert(qAbs(result["progress"].toDouble() - 0.95) < 1e-9);
    assert(result["receivedBytes"] == result["downloadTotalBytes"]);
    assert(result["downloadedSize"] == result["downloadTotalSize"]);
    application["phase"] = "failed";
    assert(transactionStages({runtime, application}, "failed")["installCompleted"].toInt() == 1);
    application["phase"] = "complete";
    assert(transactionStages({runtime, application}, "complete")["installProgress"].toDouble() == 1);
    assert(transactionStages({runtime, application}, "complete")["progress"].toDouble() == 0.99); // Await successful result.
    application["action"] = "install-bundle";
    assert(!transactionStages({application}, "install")["hasDownload"].toBool());
    application["phase"] = "install"; application["progress"] = 0.5;
    result = transactionStages({application}, "install");
    assert(result["receivedBytes"].toULongLong() == 0); // Bundle import is not network traffic.
    assert(result["downloadTotalBytes"].toULongLong() == 0);
    assert(result["progress"].toDouble() == 0.45);
    result = transactionStages({runtime, application}, "install");
    assert(result["hasDownload"].toBool()); // A local bundle may still need an online runtime.
    assert(result["receivedBytes"].toULongLong() == 200 && result["downloadTotalBytes"].toULongLong() == 200);
    assert(result["installCompleted"].toInt() == 1 && result["installTotal"].toInt() == 2);
    runtime["receivedBytes"] = 0;
    result = transactionStages({runtime, application}, "install");
    assert(!result["hasDownload"].toBool()); // Entirely reused/cached payload.
    application["phase"] = "waiting"; application["action"] = "install"; application["downloadBytes"] = 0;
    application["downloadProgress"] = 0;
    runtime["downloadBytes"] = 1e12;
    assert(transactionStages({runtime, application}, "preparing")["downloadProgress"].toDouble() <= 0.99);
    const QVariantMap removal{{"action", "uninstall"}, {"phase", "complete"}};
    assert(transactionStages({runtime, removal}, "complete")["installTotal"].toInt() == 1);
    application["downloadBytes"] = 128000000; application["receivedBytes"] = 128000000;
    application["downloadProgress"] = 1; application["phase"] = "install";
    result = transactionStages({application}, "install");
    assert(result["downloadedSize"].toString() == "128.00 MB" && result["downloadTotalSize"].toString() == "128.00 MB");
    assert(result["progress"].toDouble() == 0.9 && result["installCompleted"].toInt() == 0);
    application["downloadBytes"] = 100; application["receivedBytes"] = 120; application["downloadProgress"] = 0.9;
    result = transactionStages({application}, "download");
    assert(result["receivedBytes"].toULongLong() <= result["downloadTotalBytes"].toULongLong());
    assert(transactionStages({}, "preparing")["progress"].toDouble() == 0);
    QLocale::setDefault(QLocale("de_DE"));
    assert(transactionStages({application}, "download")["downloadedSize"].toString().contains(','));
    qInfo("PASS: unified weighted progress, aggregate/actual bytes, no early 100%%, dependencies, cached transfers, local bundles and completion");
}
