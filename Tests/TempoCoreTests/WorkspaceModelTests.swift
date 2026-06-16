import Testing
@testable import TempoCore

@Suite("WorkspaceModel")
struct WorkspaceModelTests {
    @Test("a new model has the given active workspace and no windows")
    func empty() {
        let model = WorkspaceModel(active: "1")
        #expect(model.active == "1")
        #expect(model.visibleWindows == [])
        #expect(model.hiddenWindows == [])
    }

    @Test("windows in the active workspace are visible; the rest are hidden")
    func visibility() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        model.add(30, to: "2")
        #expect(model.visibleWindows == [10, 20])
        #expect(model.hiddenWindows == [30])
    }

    @Test("switching workspace recomputes visibility")
    func switching() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(30, to: "2")
        model.switchTo("2")
        #expect(model.active == "2")
        #expect(model.visibleWindows == [30])
        #expect(model.hiddenWindows == [10])
    }

    @Test("moving a window to the active workspace makes it visible")
    func moveToActive() {
        var model = WorkspaceModel(active: "1")
        model.add(30, to: "2")
        model.move(30, to: "1")
        #expect(model.visibleWindows == [30])
    }

    @Test("removing a window drops it from all queries")
    func removal() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.remove(10)
        #expect(model.visibleWindows == [])
    }

    @Test("placedWindows joins assignments with the info cache, sorted by workspace then id")
    func placedWindowsJoin() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "2")
        model.add(20, to: "1")
        model.add(30, to: "2")
        let infos: [WindowID: WindowInfo] = [
            10: WindowInfo(bundleId: "com.brave.Browser", title: "ChatGPT", subrole: .standardWindow),
            20: WindowInfo(bundleId: "com.apple.mail", title: "Inbox", subrole: .standardWindow),
            30: WindowInfo(bundleId: "com.apple.notes", title: "todo", subrole: .standardWindow),
        ]
        #expect(model.placedWindows(using: infos) == [
            PlacedWindow(window: infos[20]!, workspace: "1"),
            PlacedWindow(window: infos[10]!, workspace: "2"),
            PlacedWindow(window: infos[30]!, workspace: "2"),
        ])
    }

    @Test("placedWindows skips assigned windows whose info is missing")
    func placedWindowsSkipsMissing() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(99, to: "1")
        let infos: [WindowID: WindowInfo] = [
            10: WindowInfo(bundleId: "com.apple.mail", title: "", subrole: .standardWindow),
        ]
        #expect(model.placedWindows(using: infos) == [
            PlacedWindow(window: infos[10]!, workspace: "1"),
        ])
    }

    @Test("back-and-forth returns to the previously active workspace")
    func backAndForth() {
        var model = WorkspaceModel(active: "1")
        model.switchTo("3")
        model.switchBackAndForth()
        #expect(model.active == "1")
        model.switchBackAndForth()
        #expect(model.active == "3")
    }
}
