import AppKit
import ApplicationServices
import TempoCore

/// The long-running Tempo daemon: adopts every regular app's windows into the
/// active workspace, applies the active workspace's tiling, shows a menu bar
/// item, and takes commands over a FIFO. New windows always land in the active
/// workspace; the user moves them around with chord bindings.
@MainActor
final class TempoAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: WindowController!
    private var statusItem: NSStatusItem!
    private var fifoSource: DispatchSourceRead?
    private var fifoFD: Int32 = -1
    private let fifoPath: String
    private var eventTap: CFMachPort?
    private var eventTapThread: Thread?
    private let config: Config = loadDaemonConfig()
    private var axObserverThread: Thread?
    private let axHandle = AXThreadHandle()
    private var appObservers: [pid_t: AXObserver] = [:]
    private var workspaceLaunchObserver: NSObjectProtocol?
    private var workspaceTermObserver: NSObjectProtocol?
    private var workspaceActivateObserver: NSObjectProtocol?
    private var paused = false

    init(fifoPath: String) {
        self.fifoPath = fifoPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `AXIsProcessTrustedWithOptions` with the prompt option asks macOS to surface
        // its Accessibility-permission dialog the first time an unauthorized binary
        // runs. Without the prompt option (`AXIsProcessTrusted()`) the daemon just
        // silently exits, which is hostile for a fresh install — the user sees only
        // the launchd retry loop with no UI cue.
        let opts: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        guard AXIsProcessTrustedWithOptions(opts) else {
            log("Accessibility permission required — grant it in System Settings > Privacy & Security > Accessibility.")
            NSApp.terminate(nil)
            return
        }

        let active = config.defaultWorkspace ?? "1"
        controller = WindowController(active: active, area: AXEngine.mainDisplayArea())

        setupAXObservers()
        controller.apply()

        setupMenuBar()
        setupFIFO()
        startEventTap()
        log("tempo daemon started — active workspace \(controller.active), fifo \(fifoPath)")
    }

    /// Dialog/floating subroles auto-float. Everything else tiles.
    private func shouldFloat(_ info: WindowInfo) -> Bool {
        switch info.subrole {
        case .dialog, .floatingWindow: return true
        default: return false
        }
    }

    /// Install per-app AXObservers on a dedicated CFRunLoop thread (the gotcha-proven
    /// pattern from the event tap: NSApp's main run loop doesn't service manually-added
    /// CFRunLoop sources from a CLI-launched process). Enumerates the existing windows
    /// of every running app, then sits and watches for create/destroy/title events.
    private func setupAXObservers() {
        let handle = axHandle
        let thread = Thread {
            handle.runLoop = CFRunLoopGetCurrent()
            handle.ready.signal()
            // Keep the run loop alive even with no observers — add a no-op port source.
            let port = CFRunLoopSourceCreate(nil, 0, &handle.noopSourceContext)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), port, .defaultMode)
            CFRunLoopRun()
        }
        thread.name = "tempo.ax-observer"
        thread.start()
        axObserverThread = thread
        _ = handle.ready.wait(timeout: .now() + 1.0)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            addAppObserver(for: app)
            enumerateExistingWindows(of: app, applyAndPublish: false)
        }

        let nc = NSWorkspace.shared.notificationCenter
        workspaceLaunchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            // Give the launching app a moment to finish bringing up its AX tree.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    self?.addAppObserver(for: app)
                    self?.enumerateExistingWindows(of: app, applyAndPublish: true)
                }
            }
        }
        workspaceTermObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated { self?.appObservers[app.processIdentifier] = nil }
        }
        // Cmd+Tab / Spotlight / dock click → app becomes frontmost. macOS posts a
        // didActivateApplicationNotification reliably for cross-app focus changes
        // (the per-app AXObserver focus-changed notification is unreliable here).
        workspaceActivateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated { self?.handleAppActivated(app) }
        }
    }

    /// Cross-app focus follow: when `app` becomes frontmost (Cmd+Tab, Spotlight),
    /// look up its focused window's workspace and switch if different. No-op when
    /// the focused window isn't tracked or its workspace is already active.
    ///
    /// macOS fires this notification for every app activation including system
    /// services and apps without windows. Force-casting the focused-window
    /// attribute crashes the daemon if it isn't an AXUIElement (or absent);
    /// guard with CFGetTypeID and skip cleanly. Also guard against re-entrancy
    /// from our own `controller.switchTo` → `AXEngine.focus` → activate chain.
    private var inAppActivatedHandler = false
    fileprivate func handleAppActivated(_ app: NSRunningApplication) {
        if inAppActivatedHandler { return }
        inAppActivatedHandler = true
        defer { inAppActivatedHandler = false }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let raw = winRef,
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return }
        let window = raw as! AXUIElement
        guard let id = controller.windowID(matching: window),
              let target = controller.workspace(of: id),
              target != controller.active else { return }
        controller.switchTo(target, focusing: id)
        updateMenuBar()
        log("focus follow (app activated \(app.bundleIdentifier ?? "?")) -> workspace \(target)")
    }

    private func addAppObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard appObservers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success,
              let obs = observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, refcon)
        // Fires when the user focuses a different window of this app (Cmd+Tab,
        // Spotlight, dock click). We use it to follow focus across workspaces.
        AXObserverAddNotification(obs, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        if let rl = axHandle.runLoop {
            CFRunLoopAddSource(rl, AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        appObservers[pid] = obs
    }

    private func enumerateExistingWindows(of app: NSRunningApplication, applyAndPublish: Bool) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }
        var adopted = false
        for window in windows {
            if adoptWindow(window, applyAndPublish: false) { adopted = true }
        }
        if applyAndPublish && adopted {
            controller.apply()
        }
    }

    /// Adopt a window into the active workspace. New windows always land in
    /// whichever workspace is active when they appear — the user moves them
    /// around with `alt+shift+<key>`. No app-specific routing rules.
    @discardableResult
    private func adoptWindow(_ element: AXUIElement, applyAndPublish: Bool) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              NSRunningApplication(processIdentifier: pid) != nil,
              let id = AXEngine.windowID(element),
              !controller.knownIDs.contains(id),
              let info = AXEngine.windowInfo(element)
        else { return false }

        // Only manage real top-level windows. Chrome spawns transient AX windows
        // for WebHID/permission prompts and internal helpers: empty title, no
        // close button, churning create/destroy. Tiling those oscillates the tile
        // count, so the real window keeps resizing as they come and go. A genuine
        // window has a title or a close button (AeroSpace's isWindowHeuristic uses
        // the same close-button signal); dialogs we float are exempt.
        let manageable = shouldFloat(info) || !info.title.isEmpty || AXEngine.hasCloseButton(element)
        guard manageable else { return false }

        let target = controller.active
        controller.adopt(id, element: element, info: info, workspace: target)
        if shouldFloat(info) { controller.markFloating(id, true) }
        subscribeWindowEvents(element: element, pid: pid)

        let floatTag = shouldFloat(info) ? " (floating)" : ""
        log("new window \(info.bundleId) [\(info.title)] -> workspace \(target)\(floatTag)")

        if applyAndPublish && !paused {
            controller.apply()
        }
        return true
    }

    private func subscribeWindowEvents(element: AXUIElement, pid: pid_t) {
        guard let observer = appObservers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXTitleChangedNotification as CFString, refcon)
    }

    /// Symmetric pair to `subscribeWindowEvents` — call from the destroyed-notification
    /// handler, before `controller.forget`, so the same observer that received the create
    /// also drops the per-window registrations. Otherwise long-running apps (browser,
    /// editor) accumulate stale subscriptions for every window they ever opened.
    private func unsubscribeWindowEvents(element: AXUIElement, pid: pid_t) {
        guard let observer = appObservers[pid] else { return }
        AXObserverRemoveNotification(observer, element, kAXUIElementDestroyedNotification as CFString)
        AXObserverRemoveNotification(observer, element, kAXTitleChangedNotification as CFString)
    }

    fileprivate func handleAXNotification(name: String, element: AXUIElement) {
        switch name {
        case kAXWindowCreatedNotification:
            adoptWindow(element, applyAndPublish: true)
        case kAXUIElementDestroyedNotification:
            guard let id = controller.windowID(matching: element) else { return }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            unsubscribeWindowEvents(element: element, pid: pid)
            controller.forget(id)
            if !paused { controller.apply() }
            log("window closed -> id \(id) forgotten")
        case kAXTitleChangedNotification:
            guard let id = controller.windowID(matching: element),
                  let info = AXEngine.windowInfo(element) else { return }
            _ = controller.setInfo(info, for: id)
        case kAXFocusedWindowChangedNotification:
            // Cmd+Tab / Spotlight / dock click into a window on a different workspace
            // → follow focus across workspaces. The user already focused the specific
            // window they wanted; don't second-guess by calling focusFirstTracked.
            guard let id = controller.windowID(matching: element),
                  let target = controller.workspace(of: id),
                  target != controller.active else { return }
            controller.switchTo(target, focusing: id)
            updateMenuBar()
            log("focus follow -> workspace \(target) (window \(id))")
        default: break
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBar()
    }

    private func updateMenuBar() {
        let icon = paused ? "⏸" : "T"
        statusItem.button?.title = "\(icon) \(controller.active)"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let pause = NSMenuItem(
            title: paused ? "Resume Tempo" : "Pause Tempo",
            action: #selector(togglePauseFromMenu), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())

        let wsMenu = NSMenu()
        let listed = config.workspaces
        if listed.isEmpty {
            wsMenu.addItem(NSMenuItem(
                title: "(no workspaces in tempo.toml)", action: nil, keyEquivalent: ""))
        } else {
            for ws in listed {
                let item = NSMenuItem(
                    title: ws,
                    action: #selector(switchWorkspaceFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ws
                if ws == controller.active { item.state = .on }
                wsMenu.addItem(item)
            }
        }
        let wsItem = NSMenuItem(title: "Switch Workspace", action: nil, keyEquivalent: "")
        wsItem.submenu = wsMenu
        menu.addItem(wsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Tempo", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func togglePauseFromMenu() { togglePaused() }

    @objc private func switchWorkspaceFromMenu(_ sender: NSMenuItem) {
        guard let ws = sender.representedObject as? String else { return }
        controller.switchTo(ws); updateMenuBar()
        log("menu -> workspace \(ws)")
    }

    private func setupFIFO() {
        unlink(fifoPath)
        guard mkfifo(fifoPath, 0o600) == 0 else { log("mkfifo failed"); return }
        fifoFD = open(fifoPath, O_RDWR | O_NONBLOCK)
        guard fifoFD >= 0 else { log("fifo open failed"); return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fifoFD, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readCommands() }
        }
        source.resume()
        fifoSource = source
    }

    private func readCommands() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(fifoFD, &buffer, buffer.count)
        guard count > 0 else { return }
        let text = String(decoding: buffer[0..<count], as: UTF8.self)
        for line in text.split(separator: "\n") { handle(String(line)) }
    }

    private func handle(_ command: String) {
        let parts = command.split(separator: " ").map(String.init)
        if parts.first == "quit" { quit(); return }
        guard !paused else { log("ignored while paused: \(command)"); return }
        switch parts.first {
        case "workspace" where parts.count >= 2:
            controller.switchTo(parts[1]); updateMenuBar(); log("-> workspace \(parts[1])")
        case "back":
            controller.backAndForth(); updateMenuBar(); log("-> back")
        case "dump":
            log("=== dump ===\n\(controller.debugDump())\n=== end dump ===")
        default:
            log("unknown command: \(command)")
        }
    }

    /// Late-adopt the currently focused AX window if we've lost track of it.
    /// Chrome (and other apps with heavy startup churn) can emit spurious
    /// `kAXUIElementDestroyedNotification` for windows that stay visible — we
    /// `forget()` them, then the user's next chord fails with "no managed
    /// focused window". This re-anchors the visible window so move/focus chords
    /// keep working without forcing the user to alt-tab to refresh tracking.
    private func ensureFocusedTracked() {
        guard let window = AXEngine.focusedWindow(),
              let id = AXEngine.windowID(window),
              !controller.knownIDs.contains(id) else { return }
        adoptWindow(window, applyAndPublish: false)
    }

    fileprivate func handle(hotkey: Hotkey) {
        if case .togglePaused = hotkey {
            togglePaused()
            return
        }
        guard !paused else {
            log("hotkey ignored while paused: \(hotkey)")
            return
        }
        switch hotkey {
        case .switchWorkspace(let id):
            controller.switchTo(id); updateMenuBar()
            log("hotkey -> workspace \(id)")
        case .backAndForth:
            controller.backAndForth(); updateMenuBar()
            log("hotkey -> back")
        case .moveFocusedWindow(let target):
            ensureFocusedTracked()
            guard let focusedID = AXEngine.focusedWindowID(),
                  controller.knownIDs.contains(focusedID) else {
                log("hotkey -> move focused to \(target) (no managed focused window)")
                return
            }
            controller.moveWindow(focusedID, to: target)
            log("hotkey -> move focused (\(focusedID)) to \(target)")
        case .focusTile(let direction):
            ensureFocusedTracked()
            if controller.focusTile(direction) {
                log("hotkey -> focus tile \(direction)")
            } else {
                log("hotkey -> focus tile \(direction) (no-op)")
            }
        case .moveTile(let direction):
            ensureFocusedTracked()
            if controller.moveTile(direction) {
                log("hotkey -> move tile \(direction)")
            } else {
                log("hotkey -> move tile \(direction) (no-op)")
            }
        case .toggleTileOrientation:
            let active = controller.active
            let before = controller.orientation(of: active)
            let after: Orientation = before == .horizontal ? .vertical : .horizontal
            controller.setOrientation(after, for: active)
            log("hotkey -> toggle orientation (\(active): \(before) -> \(after))")
        case .toggleAccordion:
            let active = controller.active
            let before = controller.mode(of: active)
            let after: WorkspaceMode = before == .tiles ? .accordion : .tiles
            controller.setMode(after, for: active)
            log("hotkey -> toggle accordion (\(active): \(before) -> \(after))")
        case .toggleFullscreen:
            ensureFocusedTracked()
            if let action = controller.toggleFullscreen() {
                log("hotkey -> fullscreen \(action)")
            } else {
                log("hotkey -> fullscreen (no managed focused window in active workspace)")
            }
        case .toggleFloating:
            ensureFocusedTracked()
            if let action = controller.toggleFloating() {
                log("hotkey -> float \(action)")
            } else {
                log("hotkey -> float (no managed focused window in active workspace)")
            }
        case .togglePaused:
            break // handled at the top
        }
    }

    private func togglePaused() {
        paused.toggle()
        if paused {
            controller.restoreAllToScreen()
        } else {
            controller.apply()
        }
        updateMenuBar()
        log("hotkey -> paused: \(paused)")
    }

    fileprivate func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        log("event tap re-enabled")
    }

    /// Install a session event tap on a dedicated thread. NSApp's main run loop
    /// does not service manually-added CFRunLoop sources from a CLI-launched
    /// process, so we own the thread. Returning `nil` from the callback consumes
    /// the event so apps never see Tempo's hotkeys.
    ///
    /// The callback and thread closures live at file scope (see `tempoEventTapCallback`
    /// and `runEventTapLoop`) so Swift 6 does NOT infer them as `@MainActor` from
    /// the enclosing class. Inline closures inside a `@MainActor` method are
    /// auto-promoted and the runtime then asserts isolation when the event-tap
    /// thread dispatches the callback — crashing with `dispatch_assert_queue_fail`.
    private func startEventTap() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tempoEventTapCallback,
            userInfo: refcon
        ) else {
            log("CGEvent.tapCreate failed — accessibility permission may be insufficient")
            return
        }
        eventTap = tap
        let box = EventTapBox(port: tap)
        let thread = Thread { runEventTapLoop(box) }
        thread.name = "tempo.event-tap"
        thread.start()
        eventTapThread = thread
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

@MainActor
func runDaemon() {
    // Refuse to start if another daemon is already running. Two daemons fight
    // over the same event tap and menu-bar slot — chords get double-handled,
    // alt+h/l no-ops because each daemon sees the other's window state. The
    // lock is an advisory `flock` on `$TEMPO_HOME/tempo.lock`; macOS drops it
    // when the holder exits, so no cleanup path is needed (crash-safe).
    guard acquireDaemonLock() else {
        FileHandle.standardError.write(Data(
            "tempo daemon: another instance is already running (lock held on \(daemonLockPath())). Exiting.\n".utf8))
        exit(7)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = TempoAppDelegate(fifoPath: daemonFIFOPath())
    app.delegate = delegate
    app.run()
    _ = delegate // keep alive for the run loop (NSApplication.delegate is weak)
}

/// Persistent fd for the daemon lock — owning the fd until process exit is what
/// keeps the `flock` held. Closing it (or letting it deallocate) drops the lock.
private nonisolated(unsafe) var daemonLockFD: Int32 = -1

func acquireDaemonLock() -> Bool {
    let path = daemonLockPath()
    let fd = open(path, O_RDWR | O_CREAT, 0o600)
    guard fd >= 0 else { return false }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return false
    }
    daemonLockFD = fd
    return true
}

func daemonBaseDirectory() -> String {
    let base = ProcessInfo.processInfo.environment["TEMPO_HOME"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/tempo").path
    try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    return base
}

func daemonLockPath() -> String {
    daemonBaseDirectory() + "/tempo.lock"
}

func daemonFIFOPath() -> String {
    daemonBaseDirectory() + "/tempo.cmd"
}

/// Path to the hand-edited TOML config. Missing file → empty `Config`.
func daemonConfigPath() -> String {
    daemonBaseDirectory() + "/tempo.toml"
}

/// Read and parse `tempo.toml`. Failures (missing file, syntax error) fall back to
/// an empty `Config`, logging to stderr — the daemon must boot regardless.
func loadDaemonConfig() -> Config {
    let path = daemonConfigPath()
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return Config() }
    do {
        return try ConfigParser.parse(source)
    } catch {
        FileHandle.standardError.write(Data("config: parse error in \(path): \(error)\n".utf8))
        return Config()
    }
}

/// Shared box that lets the AX-observer worker thread publish its CFRunLoop pointer
/// back to the main actor (which then attaches AX observer sources to that loop).
final class AXThreadHandle: @unchecked Sendable {
    var runLoop: CFRunLoop?
    let ready = DispatchSemaphore(value: 0)
    var noopSourceContext = CFRunLoopSourceContext()
}

/// `AXUIElement` is a CF class without a Sendable conformance — wrap it for the
/// callback → main-queue hop. The wrapper retains via the captured property.
struct SendableAXElement: @unchecked Sendable {
    let element: AXUIElement
}

/// Top-level C-callback for AX observers — captures nothing, dispatches the notification
/// onto the main queue where `handleAXNotification` lives.
let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let delegate = Unmanaged<TempoAppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    let wrapped = SendableAXElement(element: element)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            delegate.handleAXNotification(name: name, element: wrapped.element)
        }
    }
}

/// Map CGEventFlags to Tempo's pure `Modifiers` set. Free function (not a
/// method on `TempoAppDelegate`) so the CGEventTap callback running on the
/// `tempo.event-tap` thread can call it without the Swift 6 runtime asserting
/// MainActor isolation on a static method of an `@MainActor` class.
func modifiersFrom(_ flags: CGEventFlags) -> Modifiers {
    var mods: Modifiers = []
    if flags.contains(.maskAlternate)   { mods.insert(.option) }
    if flags.contains(.maskShift)       { mods.insert(.shift) }
    if flags.contains(.maskCommand)     { mods.insert(.command) }
    if flags.contains(.maskControl)     { mods.insert(.control) }
    return mods
}

/// Sendable wrapper around the `UnsafeMutableRawPointer` we use as the event
/// tap's `userInfo`. The raw pointer is opaque (it's just a back-pointer to
/// the `TempoAppDelegate`); the wrapper exists only to satisfy Swift 6's
/// sending-across-isolation check on `DispatchQueue.main.async`.
struct RefconBox: @unchecked Sendable {
    let raw: UnsafeMutableRawPointer
}

/// CGEventTap C-callback. Lives at file scope so Swift 6 does not infer it
/// as `@MainActor` from an enclosing class — defining the same body inside
/// `startEventTap()` (a `@MainActor` method) auto-promotes the closure and
/// triggers `dispatch_assert_queue_fail` on the event-tap thread.
let tempoEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        guard let raw = refcon else { return Unmanaged.passUnretained(event) }
        let box = RefconBox(raw: raw)
        DispatchQueue.main.async {
            let delegate = Unmanaged<TempoAppDelegate>.fromOpaque(box.raw).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.reenableEventTap() }
        }
        return Unmanaged.passUnretained(event)
    case .keyDown:
        guard let raw = refcon else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = modifiersFrom(event.flags)
        if let hotkey = HotkeyDecoder.decode(keyCode: keyCode, modifiers: mods) {
            let box = RefconBox(raw: raw)
            DispatchQueue.main.async {
                let delegate = Unmanaged<TempoAppDelegate>.fromOpaque(box.raw).takeUnretainedValue()
                MainActor.assumeIsolated { delegate.handle(hotkey: hotkey) }
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}

/// Sendable wrapper around `CFMachPort` — `CFMachPort` lacks a `Sendable`
/// conformance, so capturing it in the thread closure (also at file scope)
/// requires an `@unchecked Sendable` shim.
struct EventTapBox: @unchecked Sendable {
    let port: CFMachPort
}

/// Body of the event-tap thread. File scope (same reason as the callback) —
/// inlining inside the `@MainActor` `startEventTap()` auto-promotes the
/// thread closure, which then crashes the runtime when CFRunLoopRun dispatches
/// the callback off the event-tap thread.
func runEventTapLoop(_ box: EventTapBox) {
    let source = CFMachPortCreateRunLoopSource(nil, box.port, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: box.port, enable: true)
    CFRunLoopRun()
}

@discardableResult
func sendDaemonCommand(_ command: String) -> Bool {
    let fd = open(daemonFIFOPath(), O_WRONLY | O_NONBLOCK)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    let bytes = Array((command + "\n").utf8)
    return write(fd, bytes, bytes.count) == bytes.count
}
