import QtQuick

QtObject {
    id: queue
    property var jobs: []
    property bool completionSeen: false
    readonly property bool hasError: jobs.some(function(job) { return job.failed === true })
    readonly property bool buttonVisible: jobs.length > 0
    readonly property int activeCount: jobs.filter(function(job) { return job.active === true }).length
    readonly property var currentJobs: jobs.filter(function(job) { return job.active === true })
    readonly property int runningCount: currentJobs.filter(function(job) { return job.queued !== true }).length
    readonly property real progress: currentJobs.length ? currentJobs.reduce(function(total, job) {
        return total + job.progress
    }, 0) / currentJobs.length : (jobs.length ? 1 : 0)
    onActiveCountChanged: if (activeCount > 0) completionSeen = false

    function markViewed() {
        if (jobs.length && activeCount === 0) completionSeen = true
    }

}
