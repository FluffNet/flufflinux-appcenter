// Test-only executable: identical production worker, with its settings file
// redirected into the integration test's temporary directory at compile time.
#define APPCENTER_SOURCE_TEST_CONFIG qEnvironmentVariable("APPCENTER_TEST_CONFIG")
#include "../../src/flatpak_worker.cpp"
int main(int argc, char **argv) {
    if (argc != 2 || qEnvironmentVariable("APPCENTER_TEST_CONFIG").isEmpty()) return 99;
    return fluff_transaction_worker(argv[1]);
}
