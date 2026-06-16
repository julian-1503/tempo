import Testing
import Foundation
@testable import TempoCore

@Suite("Placements codec")
struct PlacementsCodecTests {
    @Test("round-trips a [PlacedWindow] through pretty/sorted-keys JSON")
    func roundtrips() throws {
        let placements = [
            PlacedWindow(window: WindowInfo(bundleId: "com.apple.mail",
                                            title: "Inbox",
                                            subrole: .standardWindow),
                         workspace: "5"),
            PlacedWindow(window: WindowInfo(bundleId: "com.brave.Browser",
                                            title: "ChatGPT",
                                            subrole: .other("AXSystemDialog")),
                         workspace: "C"),
        ]

        let data = try Placements.encodeJSON(placements)
        let decoded = try Placements.decodeJSON(data)

        #expect(decoded == placements)
    }
}
