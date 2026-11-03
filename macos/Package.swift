// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClipKeep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipKeep",
            path: "Sources/ClipKeep",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
