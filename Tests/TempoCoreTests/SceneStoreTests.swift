import Testing
import Foundation
@testable import TempoCore

@Suite("File scene store")
struct SceneStoreTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempo-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func sampleScene(_ name: String) -> Scene {
        Scene(name: name, assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5")
        ])
    }

    @Test("saves a scene and loads it back unchanged")
    func saveLoadRoundTrip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSceneStore(directory: dir)
        let scene = sampleScene("work")

        try store.save(scene)

        #expect(try store.load("work") == scene)
    }

    @Test("lists saved scene names sorted, ignoring non-json files")
    func listsNames() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSceneStore(directory: dir)
        try store.save(sampleScene("work"))
        try store.save(sampleScene("chess"))
        try Data("noise".utf8).write(to: dir.appendingPathComponent("README.md"))

        #expect(try store.list() == ["chess", "work"])
    }

    @Test("loading a missing scene throws notFound")
    func loadMissingThrows() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileSceneStore(directory: dir)

        #expect(throws: SceneStoreError.notFound("ghost")) {
            try store.load("ghost")
        }
    }

    @Test("creates the directory on save if it does not exist")
    func createsDirOnSave() throws {
        let parent = try tempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = FileSceneStore(directory: parent.appendingPathComponent("scenes"))

        try store.save(sampleScene("work"))

        #expect(try store.list() == ["work"])
    }
}
