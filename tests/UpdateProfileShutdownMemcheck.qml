import QtQuick

// Full 200-job queue, fewer page transitions for whole-library instrumentation.
// Pair with APPCENTER_PROFILE_CATALOG_LIMIT=200 to avoid spending the test
// deadline instrumenting serialization of thousands of unrelated catalog rows.
UpdateProfileShutdownOverlap { navigationTurns: 8 }
