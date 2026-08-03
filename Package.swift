// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClawdCompanion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClawdCompanion",
            path: "Sources/ClawdCompanion"
        )
    ]
)
