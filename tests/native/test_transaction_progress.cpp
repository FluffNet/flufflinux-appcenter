#include "../../src/transaction_progress.h"
#include "../../src/download_rate.h"
#include <QCoreApplication>
#include <cassert>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QLocale::setDefault(QLocale::c());
    QVariantMap language{{"ref", "runtime/org.example.App.Locale/x86_64/stable"}, {"action", "install"},
                        {"downloadBytes", 118875}, {"receivedBytes", 0}, {"downloadProgress", 0}};
    QVariantMap liveApp{{"ref", "app/org.example.App/x86_64/stable"}, {"action", "install"},
                       {"downloadBytes", 204285142}, {"receivedBytes", 0}, {"downloadProgress", 0}};
    auto sizes = transactionStages({language, liveApp}, "preparing");
    assert(sizes["sizeInfo"].toMap()["appSize"].toString() == "194.82 MiB");
    assert(sizes["sizeInfo"].toMap()["totalSize"].toString() == "194.93 MiB");
    language["receivedBytes"] = 7200; language["downloadProgress"] = 1;
    sizes = transactionStages({language, liveApp}, "download");
    assert(sizes["sizeInfo"].toMap()["totalSize"] == sizes["downloadTotalSize"]);
    assert(sizes["sizeInfo"].toMap()["totalSize"].toString() == "194.83 MiB");
    liveApp["receivedBytes"] = 1000000; liveApp["downloadProgress"] = 1;
    sizes = transactionStages({language, liveApp}, "install");
    assert(sizes["sizeInfo"].toMap()["appBytes"].toULongLong() == 1000000); // Reused payload: keep the actual count.
    assert(sizes["sizeInfo"].toMap()["totalBytes"] == sizes["receivedBytes"]);
    liveApp["action"] = "install-bundle";
    assert(!transactionStages({language, liveApp}, "install").contains("sizeInfo")); // Bundle file size is not network size.
    QVariantMap runtime{{"action", "install"}, {"downloadBytes", 300}, {"phase", "download"},
                        {"downloadProgress", 0.5}, {"receivedBytes", 100}};
    QVariantMap application{{"action", "install"}, {"downloadBytes", 100}, {"phase", "waiting"}};
    auto result = transactionStages({runtime, application}, "download");
    assert(result["downloadProgress"].toDouble() == 0.375);
    assert(!result["downloadComplete"].toBool());
    assert(qAbs(result["progress"].toDouble() - 0.3375) < 1e-9);
    assert(result["receivedBytes"].toULongLong() == 100);
    assert(result["downloadTotalBytes"].toULongLong() == 400);
    assert(result["installCompleted"].toInt() == 0 && result["installTotal"].toInt() == 2);
    runtime["phase"] = "install"; runtime["downloadProgress"] = 1; runtime["receivedBytes"] = 200;
    result = transactionStages({runtime, application}, "install");
    assert(result["downloadProgress"].toDouble() == 0.75);
    assert(result["installProgress"].toDouble() == 0); // Pull != installation.
    assert(result["downloadTotalBytes"].toULongLong() == 300); // Actual runtime + pending app estimate.
    assert(!result["downloadComplete"].toBool()); // Do not hide bytes between dependency pulls.
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
    assert(result["downloadComplete"].toBool()); // Hide bytes even while deployment continues.
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
    assert(result["downloadComplete"].toBool()); // Pure local import needs no speed label.
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
    assert(result["downloadedSize"].toString() == "122.07 MiB" && result["downloadTotalSize"].toString() == "122.07 MiB");
    assert(result["progress"].toDouble() == 0.9 && result["installCompleted"].toInt() == 0);
    application["downloadBytes"] = 100; application["receivedBytes"] = 120; application["downloadProgress"] = 0.9;
    result = transactionStages({application}, "download");
    assert(result["receivedBytes"].toULongLong() <= result["downloadTotalBytes"].toULongLong());
    application["receivedBytes"] = 190740000; application["downloadBytes"] = 1897850000;
    result = transactionStages({application}, "download");
    assert(result["downloadedSize"].toString() == "181.90 MiB");
    assert(result["downloadTotalSize"].toString() == "1.77 GiB");
    assert(result["downloadTotalSize"].toString() == downloadSizeText(application["downloadBytes"].toULongLong()));
    assert(result["downloadTotalSize"].toString() == QLocale().formattedDataSize(1897850000)); // Keep the app page's binary units.
    assert(result["downloadTotalBytes"].toULongLong() == 1897850000); // Formatting does not alter accounting.
    application["receivedBytes"] = 1000000000;
    assert(transactionStages({application}, "download")["downloadedSize"].toString() == "953.67 MiB");
    application["receivedBytes"] = 1073741824;
    assert(transactionStages({application}, "download")["downloadedSize"].toString() == "1.00 GiB");
    application["receivedBytes"] = 1023 * DownloadMebibyte;
    assert(transactionStages({application}, "download")["downloadedSize"].toString() == "1023.00 MiB");
    application["receivedBytes"] = 0;
    assert(transactionStages({application}, "download")["downloadedSize"].toString() == "0.00 MiB");
    assert(transactionStages({}, "preparing")["progress"].toDouble() == 0);
    DownloadRate rate;
    assert(rate.sample(0, 0, false) == 0);
    assert(rate.sample(500, 0, true) == 0);
    assert(rate.sample(1000, 1000000, true) == 2000000);
    assert(DownloadRate::display(2000000) == "1.91 MiB/s");
    assert(DownloadRate::display(DownloadMebibyte) == "1.00 MiB/s");
    assert(rate.sample(1500, 2000000, true) == 2000000);
    rate.sample(2000, 2000000, true);
    rate.sample(2500, 2000000, true);
    rate.sample(3000, 2000000, true);
    assert(rate.sample(3500, 2000000, true) == 0); // Stalled download, no callbacks needed.
    assert(rate.sample(3600, 2000000, false) == 0); // Deployment cannot count as transfer speed.
    assert(rate.sample(5000, 2000000, true) == 0); // Next dependency excludes deployment delay.
    assert(rate.sample(5500, 2500000, true) == 1000000);
    assert(rate.sample(5500, 2500000, true) == 1000000); // Same monotonic tick, no division by zero.
    assert(rate.sample(6000, 0, true) == 0); // Counter reset/new transaction.
    assert(rate.sample(100, 0, true) == 0); // Clock reset.
    rate = DownloadRate{};
    assert(rate.sample(100, 9000000, false) == 0); // Local imports ignored.
    assert(rate.sample(200, 10000000, false) == 0);
    QLocale::setDefault(QLocale("de_DE"));
    assert(transactionStages({application}, "download")["downloadedSize"].toString().contains(','));
    assert(transactionStages({application}, "download")["downloadTotalSize"].toString() == "1,77 GiB");
    assert(downloadSizeText(1897850000) == "1,77 GiB"); // App estimates use the same localized formatter.
    assert(DownloadRate::display(1500000) == "1,43 MiB/s");
    qInfo("PASS: unified weighted progress, aggregate/actual bytes, no early 100%%, dependencies, cached transfers, local bundles and completion");
}
