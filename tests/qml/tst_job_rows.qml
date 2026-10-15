import QtQuick
import QtTest
import "../../qml" as App

TestCase {
    name: "JobRowTransport"
    when: main.visible
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property var installSizes: ({})
        signal jobsSnapshotChanged()
        signal jobRowsChanged(var rows)
        signal installedAppsSnapshotChanged()
        signal installedAppRowsChanged(var rows)
    }
    App.Main { id: main; backend: backend; visible: true; width: 1180; height: 800 }

    function test_installed_rows_preserve_unchanged_metadata() {
        backend.installedApps = [
            {id: "a.b.One", installedVersion: "1", installation: "user"},
            {id: "a.b.Two", installedVersion: "1", installation: "user"}
        ]
        backend.installedAppsSnapshotChanged()
        const unchanged = main.installedApps[1]
        backend.installedAppRowsChanged({"0": {id: "a.b.One", installedVersion: "2", installation: "user"}})
        compare(main.findInstalled({id: "a.b.One"}).installedVersion, "2")
        verify(main.installedApps[1] === unchanged)
        backend.installedAppsChanged()
        compare(main.installedApps[0].installedVersion, "2")
        backend.installedApps = []
        backend.installedAppsSnapshotChanged()
        compare(main.installedApps.length, 0)
    }

    function test_rows_preserve_unchanged_objects_and_membership() {
        backend.jobs = [
            {index: 0, id: "a.b.One", name: "One", active: true, progress: 0},
            {index: 1, id: "a.b.Two", name: "Two", active: true, progress: 0}
        ]
        backend.jobsSnapshotChanged()
        compare(main.backendJobs.length, 2)
        const unchanged = main.backendJobs[1]
        const changed = Object.assign({}, main.backendJobs[0], {progress: 0.5})
        backend.jobRowsChanged({"0": changed})
        compare(main.backendJobs[0].progress, 0.5)
        verify(main.backendJobs[1] === unchanged)
        // The generic property notification must not overwrite row deltas.
        backend.jobsChanged()
        compare(main.backendJobs[0].progress, 0.5)
        backend.jobs = [unchanged]
        backend.jobsSnapshotChanged()
        compare(main.backendJobs.length, 1)
        compare(main.backendJobs[0].id, "a.b.Two")
        backend.jobs = []
        backend.jobsSnapshotChanged()
        compare(main.backendJobs.length, 0)
    }
    function test_lookup_and_icon_invalidation() {
        main.catalog = [{id: "a.b.One.desktop", name: "One"}]
        main.installedApps = [{id: "a.b.One", installation: "user", installedBranch: "stable"},
            {id: "a.b.One.desktop", installation: "system", installedBranch: "stable"}]
        compare(main.catalogApp("a.b.One").name, "One")
        compare(main.findInstalled({id: "a.b.One", installation: "system", installedBranch: "stable"}).installation, "system")
        const file = main.iconSource("/tmp/catalog-icon.png")
        const theme = main.iconSource("applications-internet")
        ++backend.iconRevision
        compare(main.iconSource("/tmp/catalog-icon.png"), file)
        verify(main.iconSource("applications-internet") !== theme)
        main.catalog = [{id: "a.b.Two", name: "Two"}]
        verify(main.iconSource("/tmp/catalog-icon.png") !== file)
        compare(main.catalogApp("a.b.One"), null)
        main.installedApps = []
    }
}
