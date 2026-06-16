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

    @Test("visibleWindows preserves the order in which windows were added")
    func insertionOrder() {
        var model = WorkspaceModel(active: "1")
        model.add(30, to: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        #expect(model.visibleWindows == [30, 10, 20])
    }

    @Test("moving a window between workspaces appends it to the destination order")
    func moveAppendsToDestination() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        model.add(30, to: "2")
        model.move(20, to: "2")
        #expect(model.visibleWindows == [10])
        model.switchTo("2")
        #expect(model.visibleWindows == [30, 20])
    }

    @Test("removing a window closes the gap in tile order")
    func removalClosesGap() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        model.add(30, to: "1")
        model.remove(20)
        #expect(model.visibleWindows == [10, 30])
    }

    @Test("neighbor returns the previous tile for .left and next tile for .right")
    func neighbors() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        model.add(30, to: "1")
        #expect(model.neighbor(of: 20, direction: .left) == 10)
        #expect(model.neighbor(of: 20, direction: .right) == 30)
    }

    @Test("neighbor returns nil at edges (no wrap)")
    func neighborsAtEdges() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        #expect(model.neighbor(of: 10, direction: .left) == nil)
        #expect(model.neighbor(of: 20, direction: .right) == nil)
    }

    @Test("neighbor returns nil for vertical directions in v1.1 (single-row tiles)")
    func neighborsVertical() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        #expect(model.neighbor(of: 10, direction: .up) == nil)
        #expect(model.neighbor(of: 10, direction: .down) == nil)
    }

    @Test("neighbor returns nil for an unknown window")
    func neighborUnknown() {
        let model = WorkspaceModel(active: "1")
        #expect(model.neighbor(of: 99, direction: .left) == nil)
    }

    @Test("swapWithNeighbor reorders the tile list and returns true")
    func swapTiles() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        model.add(30, to: "1")
        #expect(model.swapWithNeighbor(20, direction: .left) == true)
        #expect(model.visibleWindows == [20, 10, 30])
    }

    @Test("swapWithNeighbor returns false at edges and leaves order unchanged")
    func swapAtEdges() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        #expect(model.swapWithNeighbor(10, direction: .left) == false)
        #expect(model.visibleWindows == [10, 20])
    }

    @Test("swapWithNeighbor returns false for vertical directions in v1.1")
    func swapVertical() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        #expect(model.swapWithNeighbor(10, direction: .up) == false)
        #expect(model.swapWithNeighbor(10, direction: .down) == false)
        #expect(model.visibleWindows == [10, 20])
    }

    @Test("a workspace's tile orientation defaults to horizontal")
    func defaultOrientation() {
        let model = WorkspaceModel(active: "1")
        #expect(model.orientation(of: "1") == .horizontal)
        #expect(model.orientation(of: "2") == .horizontal)
    }

    @Test("setOrientation persists per-workspace and is independent across workspaces")
    func orientationPersistence() {
        var model = WorkspaceModel(active: "1")
        model.setOrientation(.vertical, for: "1")
        #expect(model.orientation(of: "1") == .vertical)
        #expect(model.orientation(of: "2") == .horizontal)
        model.setOrientation(.horizontal, for: "1")
        #expect(model.orientation(of: "1") == .horizontal)
    }

    @Test("neighbor in a vertical workspace navigates j/k and ignores h/l")
    func neighborVerticalAxis() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        model.add(30, to: "1")
        model.setOrientation(.vertical, for: "1")
        #expect(model.neighbor(of: 20, direction: .up) == 10)
        #expect(model.neighbor(of: 20, direction: .down) == 30)
        #expect(model.neighbor(of: 20, direction: .left) == nil)
        #expect(model.neighbor(of: 20, direction: .right) == nil)
    }

    @Test("swapWithNeighbor in a vertical workspace swaps along j/k and refuses h/l")
    func swapVerticalAxis() {
        var model = WorkspaceModel(active: "1")
        model.add(10, to: "1")
        model.add(20, to: "1")
        model.setOrientation(.vertical, for: "1")
        #expect(model.swapWithNeighbor(10, direction: .left) == false)
        #expect(model.swapWithNeighbor(10, direction: .down) == true)
        #expect(model.visibleWindows == [20, 10])
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
