import Foundation
import TempoCore

// Minimal CLI entry point. The engine + Accessibility-API shell are built in later cycles.
let version = "0.0.1"

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "--version", "version":
    print("tempo \(version)")
case "--help", "help", nil:
    print("""
    tempo \(version)
    usage: tempo <command>

    commands:
      version            print version
      (more coming: query, scene)
    """)
default:
    FileHandle.standardError.write(Data("unknown command: \(args[0])\n".utf8))
    exit(2)
}
