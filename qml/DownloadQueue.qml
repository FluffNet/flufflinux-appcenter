import QtQuick

QtObject {
    id: queue
    property var jobs: []
    // Equality of this scalar suppresses model reconciliation on progress-only
    // updates. Indices are numeric backend identities, not translated labels.
    readonly property string membership: jobs.map(job => job.index).join(",")
    readonly property var jobsByIndex: {
        const indexed = {}
        for (const job of jobs) indexed[job.index] = job
        return indexed
    }
    property bool completionSeen: false
    readonly property bool hasError: jobs.some(function(job) { return job.failed === true })
    readonly property bool buttonVisible: jobs.length > 0
    readonly property int activeCount: jobs.filter(function(job) { return job.active === true }).length
    readonly property var currentJobs: jobs.filter(function(job) { return job.active === true })
    readonly property int runningCount: currentJobs.filter(function(job) { return job.queued !== true }).length
    readonly property int currentBatch: Math.max(0, ...jobs.map(job => Number(job.queueBatch || 0)))
    readonly property var batchJobs: jobs.filter(job => Number(job.queueBatch || 0) === currentBatch)
    // Finished items stay in this batch's denominator. Averaging only active
    // jobs made the toolbar jump backwards every time an app completed.
    readonly property real progress: batchJobs.length ? batchJobs.reduce(function(total, job) {
        return total + (job.active ? Math.max(0, Math.min(0.99, Number(job.progress || 0))) : 1)
    }, 0) / batchJobs.length : 0
    onActiveCountChanged: if (activeCount > 0) completionSeen = false

    function markViewed() {
        if (jobs.length && activeCount === 0) completionSeen = true
    }

}
