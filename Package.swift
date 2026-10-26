// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cornice",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cornice", targets: ["CorniceApp"]),
        .library(name: "CorniceCore", targets: ["CorniceCore"]),
    ],
    targets: [
        .target(name: "CorniceCore"),
        .executableTarget(name: "CorniceApp", dependencies: ["CorniceCore"]),
        .testTarget(name: "CorniceCoreTests", dependencies: ["CorniceCore"]),
    ]
)
