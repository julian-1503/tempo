import Testing
import Foundation
@testable import TempoCore

struct FakeWindowSource: WindowSource {
    let windows: [WindowInfo]
    func currentWindows() throws -> [WindowInfo] { windows }
}

@Suite("Window subrole and query command")
struct QueryCommandTests {
    @Test("subrole maps to and from its AX string value")
    func subroleAXValue() {
        #expect(WindowSubrole.standardWindow.axValue == "AXStandardWindow")
        #expect(WindowSubrole.dialog.axValue == "AXDialog")
        #expect(WindowSubrole(axValue: "AXFloatingWindow") == .floatingWindow)
        #expect(WindowSubrole(axValue: "AXSomethingElse") == .other("AXSomethingElse"))
    }

    @Test("query windows emits JSON that round-trips back to the same windows")
    func queryWindowsRoundTrips() throws {
        let source = FakeWindowSource(windows: [
            WindowInfo(bundleId: "com.apple.mail", title: "Inbox", subrole: .standardWindow),
            WindowInfo(bundleId: "com.macpaw.CleanMyMac4", title: "Prefs", subrole: .dialog),
        ])

        let json = try Commands.queryWindows(source: source)
        let decoded = try JSONDecoder().decode([WindowInfo].self, from: Data(json.utf8))

        #expect(decoded == source.windows)
    }

    @Test("query windows JSON uses the AX subrole string")
    func queryWindowsUsesAXSubrole() throws {
        let source = FakeWindowSource(windows: [
            WindowInfo(bundleId: "com.apple.mail", title: "Inbox", subrole: .standardWindow),
        ])

        let json = try Commands.queryWindows(source: source)

        #expect(json.contains("AXStandardWindow"))
    }
}
