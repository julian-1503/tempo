import Foundation
import ApplicationServices
import TempoCore

let version = "0.2.4"
var args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let helpText = """
tempo \(version)
usage: tempo <command>

commands:
  version                 print version
  daemon                  run the long-running daemon (managed by launchd)
  workspace <id>          switch the daemon to workspace <id>
  back                    back-and-forth between the last two workspaces
  debug frames            dump every AX window's bundle/title/frame
  debug winpos <bundleId> print the first matching window's position + size
  debug move <bundleId> <x> <y> [<w> <h>]
                          move (and optionally resize) a window for debugging
"""

switch args.first {
case "version", "--version":
    print("tempo \(version)")

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
