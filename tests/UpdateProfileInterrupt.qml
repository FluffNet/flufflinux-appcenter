import QtQuick

// Quit while update workers, progress signals and scrolling are still active.
// Only simulated workers in the isolated update-profile executable are used.
UpdateProfile {
    Timer {
        interval: 2000
        running: phase === 3
        onTriggered: {
            if (!backend.busy || !backendJobs.some(job => job.active)) {
                console.error("PROFILE_INTERRUPT_NOT_ACTIVE")
                Qt.exit(1)
                return
            }
            console.log("PROFILE_INTERRUPT_ACTIVE", backendJobs.length)
            Qt.quit()
        }
    }
}
