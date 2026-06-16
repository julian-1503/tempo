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
    private var pollTimer: DispatchSourceTimer?
    private var infos: [WindowID: WindowInfo] = [:]
    private let statePath: String = daemonStatePath()
    private var eventTap: CFMachPort?
    private var eventTapThread: Thread?

    init(fifoPath: String) { self.fifoPath = fifoPath }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AXIsProcessTrusted() else {
            log("Accessibility permission required.")
            NSApp.terminate(nil)
            return
        }

        scene = loadStartupScene()
        let active = scene?.focusWorkspace ?? "1"
        controller = WindowController(active: active, area: AXEngine.mainDisplayArea())

        for (element, info) in AXEngine.allWindows() where isManaged(info.bundleId) {
            guard let id = AXEngine.windowID(element) else { continue }
            infos[id] = info
            controller.adopt(id, element: element, workspace: workspace(for: info))
        }
        controller.apply()
        publishState()

        startPolling()
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

    /// Poll for window changes. New windows of managed apps are routed silently (the active
    /// workspace never changes — the anti-leak guarantee); closed windows are forgotten.
    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.4, repeating: 0.4)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.resume()
        pollTimer = timer
    }

    private func poll() {
        var liveIDs = Set<WindowID>()
        var changed = false
        var titlesChanged = false
        for (element, info) in AXEngine.allWindows() where isManaged(info.bundleId) {
            guard let id = AXEngine.windowID(element) else { continue }
            liveIDs.insert(id)
            if infos[id] != info { titlesChanged = true }
            infos[id] = info
            guard !controller.knownIDs.contains(id) else { continue }
            let target = workspace(for: info)
            controller.adopt(id, element: element, workspace: target)
            changed = true
            log("new window \(info.bundleId) [\(info.title)] -> workspace \(target)" +
                (target == controller.active ? "" : " (filed, focus kept)"))
        }
        for id in controller.knownIDs.subtracting(liveIDs) {
            controller.forget(id)
            infos[id] = nil
            changed = true
        }
        if changed { controller.apply() }
        if changed || titlesChanged { publishState() }
    }

    private func isManaged(_ bundleId: String) -> Bool {
        guard let list = ProcessInfo.processInfo.environment["TEMPO_MANAGE"], !list.isEmpty else { return true }
        return list.split(separator: ",").map(String.init).contains(bundleId)
    }

    private func loadStartupScene() -> Scene? {
        guard let name = ProcessInfo.processInfo.environment["TEMPO_SCENE"] else { return nil }
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

@discardableResult
func sendDaemonCommand(_ command: String) -> Bool {
    let fd = open(daemonFIFOPath(), O_WRONLY | O_NONBLOCK)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    let bytes = Array((command + "\n").utf8)
    return write(fd, bytes, bytes.count) == bytes.count
}
