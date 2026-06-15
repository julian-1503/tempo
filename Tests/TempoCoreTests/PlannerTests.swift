import Testing
@testable import TempoCore

@Suite("Scene-activation planner")
struct PlannerTests {
    let planner = Planner()

    func window(_ bundleId: String, _ title: String = "", _ subrole: WindowSubrole = .standardWindow) -> WindowInfo {
        WindowInfo(bundleId: bundleId, title: title, subrole: subrole)
    }

    @Test("places assigned windows and hides apps with no matching window")
    func placesAssignedHidesRest() {
        let scene = Scene(name: "work", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5")
        ], hideUnassigned: true)
        let mail = window("com.apple.mail", "Inbox")
        let slack = window("com.tinyspeck.slackmacgap", "Slack")

        let plan = planner.plan(windows: [mail, slack], scene: scene)

        #expect(plan.placements == [WindowPlacement(window: mail, workspace: "5", float: false)])
        #expect(plan.hides == ["com.tinyspeck.slackmacgap"])
    }

    @Test("does not hide an app that has at least one matching window")
    func keepsAppWithAMatchingWindow() {
        let scene = Scene(name: "work", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "Allpoint"), workspace: "A")
        ], hideUnassigned: true)
        let work = window("com.brave.Browser", "Allpoint Dashboard")
        let personal = window("com.brave.Browser", "Reddit")

        let plan = planner.plan(windows: [work, personal], scene: scene)

        #expect(plan.placements == [WindowPlacement(window: work, workspace: "A", float: false)])
        #expect(plan.hides.isEmpty)
    }

    @Test("hides nothing when hideUnassigned is false")
    func hidesNothingWhenDisabled() {
        let scene = Scene(name: "loose", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5")
        ], hideUnassigned: false)
        let mail = window("com.apple.mail", "Inbox")
        let slack = window("com.tinyspeck.slackmacgap", "Slack")

        let plan = planner.plan(windows: [mail, slack], scene: scene)

        #expect(plan.placements == [WindowPlacement(window: mail, workspace: "5", float: false)])
        #expect(plan.hides.isEmpty)
    }

    @Test("a dialog window is placed as floating")
    func dialogPlacedFloating() {
        let scene = Scene(name: "work", assignments: [
            Assignment(match: WindowMatch(bundleId: "com.macpaw.CleanMyMac4"), workspace: "G")
        ])
        let dialog = window("com.macpaw.CleanMyMac4", "Preferences", .dialog)

        let plan = planner.plan(windows: [dialog], scene: scene)

        #expect(plan.placements == [WindowPlacement(window: dialog, workspace: "G", float: true)])
    }
}
