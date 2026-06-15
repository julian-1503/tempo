import Testing
import Foundation
@testable import TempoCore

@Suite("Scene JSON load/save")
struct SceneCodecTests {
    @Test("loads a valid Scene from JSON")
    func loadsValid() throws {
        let json = """
        {
          "name": "work",
          "hideUnassigned": true,
          "assignments": [
            { "match": { "bundleId": "com.brave.Browser", "titleRegex": "Allpoint" }, "workspace": "A" },
            { "match": { "bundleId": "com.apple.mail" }, "workspace": "5", "float": false }
          ]
        }
        """
        let scene = try Scene.load(fromJSON: Data(json.utf8))

        #expect(scene == Scene(name: "work", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "Allpoint"), workspace: "A"),
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5", float: false),
        ], hideUnassigned: true))
    }

    @Test("defaults hideUnassigned to true and float to false when omitted")
    func appliesDefaults() throws {
        let json = """
        { "name": "min", "assignments": [ { "match": { "bundleId": "com.apple.mail" }, "workspace": "5" } ] }
        """
        let scene = try Scene.load(fromJSON: Data(json.utf8))

        #expect(scene.hideUnassigned == true)
        #expect(scene.assignments.first?.float == false)
    }

    @Test("round-trips through encode and decode")
    func roundTrips() throws {
        let scene = Scene(name: "work", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "ChatGPT"),
                       workspace: "C", float: true),
        ], hideUnassigned: false)

        let decoded = try Scene.load(fromJSON: scene.encodedJSON())

        #expect(decoded == scene)
    }

    @Test("rejects an assignment whose matcher has no fields")
    func rejectsEmptyMatch() {
        let json = """
        { "name": "bad", "assignments": [ { "match": {}, "workspace": "A" } ] }
        """
        #expect(throws: SceneCodingError.emptyMatch) {
            try Scene.load(fromJSON: Data(json.utf8))
        }
    }

    @Test("rejects an empty Scene name")
    func rejectsEmptyName() {
        let json = #"{ "name": "", "assignments": [] }"#
        #expect(throws: SceneCodingError.emptyName) {
            try Scene.load(fromJSON: Data(json.utf8))
        }
    }

    @Test("rejects an assignment with an empty workspace")
    func rejectsEmptyWorkspace() {
        let json = """
        { "name": "bad", "assignments": [ { "match": { "bundleId": "x" }, "workspace": "" } ] }
        """
        #expect(throws: SceneCodingError.emptyWorkspace) {
            try Scene.load(fromJSON: Data(json.utf8))
        }
    }
}
