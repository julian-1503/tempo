// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tempo",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, dependency-free domain + decision logic. Fully unit-testable.
        .target(name: "TempoCore"),

        // CLI + engine shell (Accessibility API side effects live here).
        .executableTarget(
            name: "tempo",
            dependencies: ["TempoCore"]
        ),

        .testTarget(
            name: "TempoCoreTests",
            dependencies: ["TempoCore"]
        ),
    ]
)
