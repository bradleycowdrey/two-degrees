// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TwoDegrees",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TwoDegrees", path: "Sources/TwoDegrees")
    ]
)
