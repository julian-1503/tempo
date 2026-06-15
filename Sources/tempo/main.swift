import Foundation
import TempoCore

let version = "0.0.1"
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
        case "apply", "create":
            fail(engineMissing, code: 3)
        default:
            fail("unknown scene command: \(sub)")
        }
    } catch SceneStoreError.notFound(let name) {
        fail("scene not found: \(name)", code: 4)
    } catch {
        fail("error: \(error)")
    }

case "help", "--help", nil:
    print(helpText)

default:
    fail("unknown command: \(args[0])")
}
