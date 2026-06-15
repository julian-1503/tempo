import Testing
@testable import TempoCore

@Suite("Router decisions")
struct RouterTests {
    let router = Router()

    func scene(_ assignments: [Assignment], hideUnassigned: Bool = true) -> Scene {
        Scene(name: "test", assignments: assignments, hideUnassigned: hideUnassigned)
    }

    @Test("routes a matched window to its workspace, silently, when that workspace is not active")
    func routesMatchedToNonActiveSilently() {
        let s = scene([
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "ChatGPT"),
                       workspace: "C")
        ])
        let window = WindowInfo(bundleId: "com.brave.Browser",
                                title: "ChatGPT - a conversation",
                                subrole: .standardWindow)

        let decision = router.decide(for: window, scene: s, activeWorkspace: "A")

        #expect(decision == .route(to: "C", silent: true, float: false))
    }

    @Test("routes non-silently when the target workspace is already active")
    func routesToActiveNonSilently() {
        let s = scene([
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5")
        ])
        let window = WindowInfo(bundleId: "com.apple.mail", title: "Inbox", subrole: .standardWindow)

        let decision = router.decide(for: window, scene: s, activeWorkspace: "5")

        #expect(decision == .route(to: "5", silent: false, float: false))
    }

    @Test("shows an unmatched window in the current workspace instead of hiding it")
    func unmatchedShowsInCurrent() {
        let s = scene([
            Assignment(match: WindowMatch(bundleId: "com.apple.mail"), workspace: "5")
        ])
        let window = WindowInfo(bundleId: "com.unknown.app", title: "Scratch", subrole: .standardWindow)

        let decision = router.decide(for: window, scene: s, activeWorkspace: "A")

        #expect(decision == .showInCurrent(float: false))
    }

    @Test("a composite matcher requires both bundle id and title to match")
    func compositeRequiresBoth() {
        let s = scene([
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "ChatGPT"),
                       workspace: "C")
        ])
        // Same browser, different title -> the composite assignment must not match.
        let window = WindowInfo(bundleId: "com.brave.Browser", title: "Hacker News", subrole: .standardWindow)

        let decision = router.decide(for: window, scene: s, activeWorkspace: "A")

        #expect(decision == .showInCurrent(float: false))
    }

    @Test("a more specific matcher wins over a less specific one")
    func moreSpecificWins() {
        let s = scene([
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser"), workspace: "G"),
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser", titleRegex: "ChatGPT"),
                       workspace: "C"),
        ])
        let window = WindowInfo(bundleId: "com.brave.Browser", title: "ChatGPT", subrole: .standardWindow)

        let decision = router.decide(for: window, scene: s, activeWorkspace: "A")

        #expect(decision == .route(to: "C", silent: true, float: false))
    }

    @Test("a dialog window is routed as floating")
    func dialogFloats() {
        let s = scene([
            Assignment(match: WindowMatch(bundleId: "com.macpaw.CleanMyMac4"), workspace: "G")
        ])
        let window = WindowInfo(bundleId: "com.macpaw.CleanMyMac4", title: "Preferences", subrole: .dialog)

        let decision = router.decide(for: window, scene: s, activeWorkspace: "A")

        #expect(decision == .route(to: "G", silent: true, float: true))
    }

    @Test("on an equal-specificity tie, the first matching assignment wins")
    func firstWinsOnTie() {
        let s = scene([
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser"), workspace: "A"),
            Assignment(match: WindowMatch(bundleId: "com.brave.Browser"), workspace: "B"),
        ])
        let window = WindowInfo(bundleId: "com.brave.Browser", title: "anything", subrole: .standardWindow)

        let decision = router.decide(for: window, scene: s, activeWorkspace: "Z")

        #expect(decision == .route(to: "A", silent: true, float: false))
    }
}
