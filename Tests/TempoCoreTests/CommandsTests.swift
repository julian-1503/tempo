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
