import Testing
import Foundation
@testable import TempoCore

@Suite("Scene commands")
struct CommandsTests {
    func tempStore() throws -> FileSceneStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempo-cmd-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileSceneStore(directory: dir)
    }

    @Test("renders a scene as a workspace-grouped ASCII list, sorted by workspace")
    func rendersAscii() {
        let scene = Scene(name: "work", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5"),
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "Allpoint"), workspace: "A"),
            Assignment(match: WindowMatch(bundleId: "com.macpaw.CleanMyMac4"), workspace: "G", float: true),
        ], hideUnassigned: true)

        let out = Commands.renderScene(scene)

        #expect(out == """
        Scene: work [hide unassigned]
          [5] com.apple.mail
          [A] com.brave.Browser ~Allpoint
          [G] com.macpaw.CleanMyMac4 (float)
        """)
    }

    func placed(_ bundleId: String, _ title: String, _ workspace: WorkspaceID) -> PlacedWindow {
        PlacedWindow(window: WindowInfo(bundleId: bundleId, title: title, subrole: .standardWindow),
                     workspace: workspace)
    }

    @Test("single-workspace bundle snapshots as a bundleId-only assignment, deduped across windows")
    func snapshotSingleWorkspaceUsesBundleId() {
        let placements = [
            placed("com.apple.mail", "Inbox", "5"),
            placed("com.apple.mail", "Sent", "5"),  // same bundle+workspace dedupes
        ]
        #expect(Commands.sceneFromPlacements(placements, name: "snap") == Scene(name: "snap", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5"),
        ], hideUnassigned: true))
    }

    @Test("multi-workspace bundle snapshots as one titleRegex assignment per window, sorted")
    func snapshotMultiWorkspaceUsesTitleRegex() {
        let placements = [
            placed("com.apple.mail", "Inbox", "5"),
            placed("com.brave.Browser", "Allpoint", "A"),
            placed("com.brave.Browser", "Reddit", "A"),
            placed("com.brave.Browser", "ChatGPT", "C"),
        ]

        #expect(Commands.sceneFromPlacements(placements, name: "snap") == Scene(name: "snap", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5"),
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "Allpoint"), workspace: "A"),
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "Reddit"), workspace: "A"),
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "ChatGPT"), workspace: "C"),
        ], hideUnassigned: true))
    }

    @Test("titleRegex literally escapes regex metachars so the live matcher substring-matches the original title")
    func snapshotEscapesRegexMetachars() {
        let placements = [
            placed("com.foo.app", "Hello (world)", "A"),
            placed("com.foo.app", "Other", "B"),
        ]
        let scene = Commands.sceneFromPlacements(placements, name: "snap")
        let regexes = scene.assignments.compactMap(\.match.titleRegex)
        #expect(regexes.contains("Hello \\(world\\)"))
        #expect(regexes.contains("Other"))
    }

    @Test("windows with empty titles are skipped when the bundle spans multiple workspaces")
    func snapshotSkipsEmptyTitlesInMultiWorkspace() {
        let placements = [
            placed("com.foo.app", "", "A"),
            placed("com.foo.app", "Active", "B"),
        ]
        #expect(Commands.sceneFromPlacements(placements, name: "snap") == Scene(name: "snap", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.foo.app", titleRegex: "Active"), workspace: "B"),
        ], hideUnassigned: true))
    }

    @Test("scene create from state JSON decodes placements, builds the scene, saves it")
    func sceneCreateFromState() throws {
        let store = try tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let placements = [placed("com.apple.mail", "Inbox", "5"), placed("com.brave.Browser", "ChatGPT", "C")]
        let stateData = try Placements.encodeJSON(placements)

        try Commands.sceneCreate(fromState: stateData, name: "morning", store: store)

        let loaded = try store.load("morning")
        // Both bundles only have windows on one workspace each → bundleId-only matchers.
        #expect(loaded == Scene(name: "morning", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5"),
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser"), workspace: "C"),
        ], hideUnassigned: true))
    }

    @Test("lists scene names as text and as json")
    func listsScenes() throws {
        let store = try tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Scene(name: "work", assignments: []))
        try store.save(Scene(name: "chess", assignments: []))

        #expect(try Commands.sceneList(store: store, json: false) == "chess\nwork")
        let json = try Commands.sceneList(store: store, json: true)
        #expect(try JSONDecoder().decode([String].self, from: Data(json.utf8)) == ["chess", "work"])
    }

    @Test("shows a scene as its canonical JSON")
    func showsScene() throws {
        let store = try tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let scene = Scene(name: "work", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5")
        ])
        try store.save(scene)

        let out = try Commands.sceneShow(store: store, name: "work")

        #expect(try Scene.load(fromJSON: Data(out.utf8)) == scene)
    }
}
