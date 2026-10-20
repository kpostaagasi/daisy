// swift-tools-version:5.9
// Daisy — an open-source, configurable alternative to Tangerine.
import PackageDescription

let package = Package(
    name: "Daisy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Daisy",
            path: "Sources/Daisy"
        )
    ]
)
