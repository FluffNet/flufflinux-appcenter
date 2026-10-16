import QtQuick
// Shorter destructor/error-checking run for instrumentation overhead.
// Pair with APPCENTER_PROFILE_ITEMS=20; full stress runs still use 200.
UpdateProfile { expectedJobs: 20; historyMs: 2000; idleMs: 2000 }
