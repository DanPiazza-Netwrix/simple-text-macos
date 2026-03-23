// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleText",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SimpleText",
            path: "Sources/SimpleText"
        )
    ]
)
