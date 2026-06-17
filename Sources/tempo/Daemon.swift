import AppKit
import ApplicationServices
import TempoCore

/// The long-running Tempo daemon: adopts managed windows into workspaces, applies the
/// active workspace's tiling, shows a menu bar item, and takes commands over a FIFO.
@MainActor
final class TempoAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: WindowController!
    private var statusItem: NSStatusItem!
    private var fifoSource: DispatchSourceRead?
    private var fifoFD: Int32 = -1
    private let fifoPath: String
    private let router = Router()
    private var scene: Scene?
    private var infos: [WindowID: WindowInfo] = [:]
    private let statePath: String = daemonStatePath()
    private var eventTap: CFMachPort?
    private var eventTapThread: Thread?
    private let config: Config = loadDaemonConfig()
    private var axObserverThread: Thread?
    private let axHandle = AXThreadHandle()
    private var appObservers: [pid_t: AXObserver] = [:]
    private var workspaceLaunchObserver: NSObjectProtocol?
    private var workspaceTermObserver: NSObjectProtocol?

    init(fifoPath: String) { self.fifoPath = fifoPath }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AXIsProcessTrusted() else {
            log("Accessibility permission required.")
            NSApp.terminate(nil)
            return
        }

        scene = loadStartupScene()
        let active = scene?.focusWorkspace ?? config.defaultWorkspace ?? "1"
        controller = WindowController(active: active, area: AXEngine.mainDisplayArea())

        setupAXObservers()
        controller.apply()
        publishState()

        setupMenuBar()
        setupFIFO()
        startEventTap()
        log("tempo daemon started — active workspace \(controller.active), fifo \(fifoPath)")
    }

    /// Where a window belongs under the current Scene (active workspace if unmatched).
    private func workspace(for info: WindowInfo) -> WorkspaceID {
        guard let scene,
              case let .route(target, _, _) = router.decide(for: info, scene: scene, activeWorkspace: controller.active)
        else { return controller.active }
        return target
    }

    /// Should this window auto-float? True for dialog/floating subroles, or when the
    /// scene's matching assignment explicitly asks for `float: true`.
    private func shouldFloat(_ info: WindowInfo) -> Bool {
        switch info.subrole {
        case .dialog, .floatingWindow: return true
        default: break
        }
        guard let scene else { return false }
        switch router.decide(for: info, scene: scene, activeWorkspace: controller.active) {
        case .route(_, _, let float):    return float
        case .showInCurrent(let float):  return float
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
            publishState()
        }
    }

    @discardableResult
    private func adoptWindow(_ element: AXUIElement, applyAndPublish: Bool) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier,
              isManaged(bundleId),
              let id = AXEngine.windowID(element),
              !controller.knownIDs.contains(id),
              let info = AXEngine.windowInfo(element)
        else { return false }

        infos[id] = info
        let target = workspace(for: info)
        controller.adopt(id, element: element, workspace: target)
        if shouldFloat(info) { controller.markFloating(id, true) }
        subscribeWindowEvents(element: element, pid: pid)

        let floatTag = shouldFloat(info) ? " (floating)" : ""
        log("new window \(info.bundleId) [\(info.title)] -> workspace \(target)" +
            (target == controller.active ? "" : " (filed, focus kept)") + floatTag)

        if applyAndPublish {
            controller.apply()
            publishState()
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
            infos[id] = nil
            controller.apply()
            publishState()
            log("window closed -> id \(id) forgotten")
        case kAXTitleChangedNotification:
            guard let id = controller.windowID(matching: element),
                  let info = AXEngine.windowInfo(element) else { return }
            if infos[id] != info {
                infos[id] = info
                publishState()
            }
        default: break
        }
    }

    /// Env `TEMPO_MANAGE` (comma-separated) wins; otherwise `[daemon] managed = [...]`
    /// from `tempo.toml`; otherwise no restriction.
    private func isManaged(_ bundleId: String) -> Bool {
        if let list = ProcessInfo.processInfo.environment["TEMPO_MANAGE"], !list.isEmpty {
            return list.split(separator: ",").map(String.init).contains(bundleId)
        }
        if let managed = config.managed { return managed.contains(bundleId) }
        return true
    }

    /// Env `TEMPO_SCENE` wins; otherwise `[daemon] default_scene = "..."` from `tempo.toml`.
    private func loadStartupScene() -> Scene? {
        let name = ProcessInfo.processInfo.environment["TEMPO_SCENE"] ?? config.defaultScene
        guard let name else { return nil }
        return try? FileSceneStore(directory: scenesDirectory()).load(name)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBar()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Tempo", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func updateMenuBar() {
        statusItem.button?.title = "T:\(controller.active)"
    }

    @objc private func quit() { NSApp.terminate(nil) }

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
        switch parts.first {
        case "workspace" where parts.count >= 2:
            controller.switchTo(parts[1]); updateMenuBar(); publishState(); log("-> workspace \(parts[1])")
        case "back":
            controller.backAndForth(); updateMenuBar(); publishState(); log("-> back")
        case "quit":
            quit()
        default:
            log("unknown command: \(command)")
        }
    }

    fileprivate func handle(hotkey: Hotkey) {
        switch hotkey {
        case .switchWorkspace(let id):
            controller.switchTo(id); updateMenuBar(); publishState()
            log("hotkey -> workspace \(id)")
        case .backAndForth:
            controller.backAndForth(); updateMenuBar(); publishState()
            log("hotkey -> back")
        case .moveFocusedWindow(let target):
            guard let focusedID = AXEngine.focusedWindowID(),
                  controller.knownIDs.contains(focusedID) else {
                log("hotkey -> move focused to \(target) (no managed focused window)")
                return
            }
            controller.moveWindow(focusedID, to: target); publishState()
            log("hotkey -> move focused (\(focusedID)) to \(target)")
        case .focusTile(let direction):
            if controller.focusTile(direction) {
                log("hotkey -> focus tile \(direction)")
            } else {
                log("hotkey -> focus tile \(direction) (no-op)")
            }
        case .moveTile(let direction):
            if controller.moveTile(direction) {
                publishState()
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
            if let action = controller.toggleFullscreen() {
                log("hotkey -> fullscreen \(action)")
            } else {
                log("hotkey -> fullscreen (no managed focused window in active workspace)")
            }
        case .toggleFloating:
            if let action = controller.toggleFloating() {
                log("hotkey -> float \(action)")
            } else {
                log("hotkey -> float (no managed focused window in active workspace)")
            }
        }
    }

    fileprivate func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        log("event tap re-enabled")
    }

    /// Map CGEventFlags to Tempo's pure `Modifiers` set.
    fileprivate static func modifiers(from flags: CGEventFlags) -> Modifiers {
        var mods: Modifiers = []
        if flags.contains(.maskAlternate)   { mods.insert(.option) }
        if flags.contains(.maskShift)       { mods.insert(.shift) }
        if flags.contains(.maskCommand)     { mods.insert(.command) }
        if flags.contains(.maskControl)     { mods.insert(.control) }
        return mods
    }

    /// Install a session event tap on a dedicated thread (NSApp's main run loop does not
    /// service manually-added CFRunLoop sources from a CLI-launched process). Returning
    /// `nil` from the callback consumes the event so apps never see Tempo's hotkeys.
    private func startEventTap() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let refcon {
                    let delegate = Unmanaged<TempoAppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { delegate.reenableEventTap() }
                    }
                }
                return Unmanaged.passUnretained(event)
            case .keyDown:
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let delegate = Unmanaged<TempoAppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let mods = TempoAppDelegate.modifiers(from: event.flags)
                if let hotkey = HotkeyDecoder.decode(keyCode: keyCode, modifiers: mods) {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { delegate.handle(hotkey: hotkey) }
                    }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            log("CGEvent.tapCreate failed — accessibility permission may be insufficient")
            return
        }
        eventTap = tap
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "tempo.event-tap"
        thread.start()
        eventTapThread = thread
    }

    /// Atomically rewrite `state.json` with the current `[PlacedWindow]` snapshot.
    /// Consumed by `tempo scene create --from-current` and by external tools.
    private func publishState() {
        do {
            let data = try Placements.encodeJSON(controller.placedWindows(using: infos))
            let final = URL(fileURLWithPath: statePath)
            let tmp = final.deletingLastPathComponent()
                .appendingPathComponent(".\(final.lastPathComponent).tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(final, withItemAt: tmp)
        } catch {
            log("publishState failed: \(error)")
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

@MainActor
func runDaemon() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = TempoAppDelegate(fifoPath: daemonFIFOPath())
    app.delegate = delegate
    app.run()
    _ = delegate // keep alive for the run loop (NSApplication.delegate is weak)
}

func daemonBaseDirectory() -> String {
    let base = ProcessInfo.processInfo.environment["TEMPO_HOME"]
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/tempo").path
    try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    return base
}

func daemonFIFOPath() -> String {
    daemonBaseDirectory() + "/tempo.cmd"
}

/// File the daemon atomically rewrites with the current `[PlacedWindow]` JSON on every state change.
/// Consumed by `scene create --from-current`; absence implies the daemon isn't running.
func daemonStatePath() -> String {
    daemonBaseDirectory() + "/state.json"
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

@discardableResult
func sendDaemonCommand(_ command: String) -> Bool {
    let fd = open(daemonFIFOPath(), O_WRONLY | O_NONBLOCK)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    let bytes = Array((command + "\n").utf8)
    return write(fd, bytes, bytes.count) == bytes.count
}
