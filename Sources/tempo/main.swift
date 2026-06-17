import Foundation
import ApplicationServices
import TempoCore

let version = "0.1.10"
var args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func takeFlag(_ name: String, from args: inout [String]) -> Bool {
    if let index = args.firstIndex(of: name) { args.remove(at: index); return true }
    return false
}

/// Scenes live in $TEMPO_HOME/scenes (default ~/.config/tempo/scenes).
func scenesDirectory() -> URL {
    let base = ProcessInfo.processInfo.environment["TEMPO_HOME"].map(URL.init(fileURLWithPath:))
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/tempo")
    return base.appendingPathComponent("scenes")
}

let helpText = """
tempo \(version)
usage: tempo <command>

commands:
  version                      print version
  query windows [--json]       list open windows (needs the engine)
  scene list [--json]          list saved scenes
  scene show <name>            print a scene as JSON
  scene render <name>          draw a scene as an ASCII workspace view
  scene apply <name>           activate a scene (needs the engine)
  scene create --from-current <name>
                               snapshot the live arrangement (needs the engine)
"""

let engineMissing = "this command needs the Accessibility engine, which is not built yet"

let store = FileSceneStore(directory: scenesDirectory())

switch args.first {
case "version", "--version":
    print("tempo \(version)")

case "query":
    guard args.count >= 2, args[1] == "windows" else { fail("usage: tempo query windows [--json]") }
    do {
        print(try Commands.queryWindows(source: AXWindowSource()))
    } catch EngineError.accessibilityNotTrusted {
        fail("""
        Accessibility permission required.
        Grant it in System Settings › Privacy & Security › Accessibility, then re-run.
        """, code: 5)
    } catch {
        fail("error: \(error)")
    }

case "scene":
    guard args.count >= 2 else { fail("usage: tempo scene <list|show|render|apply|create> ...") }
    let sub = args[1]
    let json = takeFlag("--json", from: &args)
    do {
        switch sub {
        case "list":
            print(try Commands.sceneList(store: store, json: json))
        case "show":
            guard args.count >= 3 else { fail("usage: tempo scene show <name> [--json]") }
            print(try Commands.sceneShow(store: store, name: args[2]))
        case "render":
            guard args.count >= 3 else { fail("usage: tempo scene render <name>") }
            print(Commands.renderScene(try store.load(args[2])))
        case "apply":
            guard args.count >= 3 else { fail("usage: tempo scene apply <name>") }
            guard AXIsProcessTrusted() else { fail("Accessibility permission required.", code: 5) }
            SceneApplier.apply(try store.load(args[2]))
            print("applied scene: \(args[2])")
        case "create":
            guard args.count >= 4, args[2] == "--from-current" else {
                fail("usage: tempo scene create --from-current <name>")
            }
            let name = args[3]
            guard let stateData = try? Data(contentsOf: URL(fileURLWithPath: daemonStatePath())) else {
                fail("tempo daemon is not running (no state file at \(daemonStatePath()))", code: 6)
            }
            try Commands.sceneCreate(fromState: stateData, name: name, store: store)
            print("created scene: \(name)")
        default:
            fail("unknown scene command: \(sub)")
        }
    } catch SceneStoreError.notFound(let name) {
        fail("scene not found: \(name)", code: 4)
    } catch {
        fail("error: \(error)")
    }

case "debug":
    guard AXIsProcessTrusted() else { fail("Accessibility permission required.", code: 5) }
    guard args.count >= 2 else { fail("usage: tempo debug <winpos|move|frames> ...") }
    let sub = args[1]
    if sub == "frames" {
        let area = AXEngine.mainDisplayArea()
        print("display: \(Int(area.x)),\(Int(area.y)) \(Int(area.width))x\(Int(area.height))")
        for (element, info) in AXEngine.allWindows() {
            let p = AXEngine.position(element) ?? .zero
            let s = AXEngine.size(element) ?? .zero
            print("\(info.bundleId) [\(info.title)] @ \(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height))")
        }
        break
    }
    guard args.count >= 3 else { fail("usage: tempo debug <winpos|move> <bundleId> [x y]") }
    let bundleId = args[2]
    guard let window = AXEngine.firstWindow(bundleId: bundleId) else {
        fail("no window found for \(bundleId)", code: 4)
    }
    switch sub {
    case "winpos":
        let p = AXEngine.position(window) ?? .zero
        let s = AXEngine.size(window) ?? .zero
        print("\(Int(p.x)) \(Int(p.y)) \(Int(s.width)) \(Int(s.height))")
    case "move":
        guard args.count >= 5, let x = Double(args[3]), let y = Double(args[4]) else {
            fail("usage: tempo debug move <bundleId> <x> <y> [w h]", code: 2)
        }
        if args.count >= 7, let w = Double(args[5]), let h = Double(args[6]) {
            AXEngine.setSize(window, CGSize(width: w, height: h))
        }
        let ok = AXEngine.setPosition(window, CGPoint(x: x, y: y))
        let p = AXEngine.position(window) ?? .zero
        print(ok ? "moved -> \(Int(p.x)) \(Int(p.y))" : "move failed")
    default:
        fail("unknown debug command: \(sub)")
    }

case "daemon":
    runDaemon()

case "workspace":
    guard args.count >= 2 else { fail("usage: tempo workspace <id>") }
    if !sendDaemonCommand("workspace \(args[1])") { fail("tempo daemon is not running", code: 6) }

case "back":
    if !sendDaemonCommand("back") { fail("tempo daemon is not running", code: 6) }

case "help", "--help", nil:
    print(helpText)

default:
    fail("unknown command: \(args[0])")
}
