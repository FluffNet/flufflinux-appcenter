import QtQuick

QtObject {
    id: queue
    property var jobs: []
    property bool simulated: false
    property real elapsed: 0
    readonly property int activeCount: jobs.filter(function(job) { return job.progress < 1 }).length
    readonly property real progress: jobs.length ? jobs.reduce(function(total, job) {
        return total + job.progress
    }, 0) / jobs.length : 0

    function startDemo() {
        simulated = true
        elapsed = 0
        updateDemo(0)
    }

    function updateDemo(seconds) {
        elapsed = seconds
        const names = ["Firefox", "VLC", "SuperTuxKart"]
        const durations = [60, 90, 120]
        jobs = names.map(function(name, index) {
            const progress = Math.min(1, Math.max(0, seconds / durations[index]))
            return { name: name, progress: progress,
                status: progress >= 1 ? qsTr("Complete")
                      : progress >= 0.75 ? qsTr("Installing…") : qsTr("Downloading…") }
        })
    }

    property Timer ticker: Timer {
        interval: 100
        running: queue.simulated && queue.activeCount > 0
        repeat: true
        onTriggered: queue.updateDemo(queue.elapsed + interval / 1000)
    }
}
