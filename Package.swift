// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cornice",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cornice", targets: ["CorniceApp"]),
        .library(name: "CorniceCore", targets: ["CorniceCore"]),
        .library(name: "CorniceKit", targets: ["CorniceKit"]),
    ],
    targets: [
        .target(name: "CorniceKit"),
        .target(name: "CorniceCore"),
        .target(name: "CorniceHost", dependencies: ["CorniceCore", "CorniceKit"]),
        .target(
            name: "ExampleWidgetWidget",
            dependencies: ["CorniceKit"],
            path: "Widgets/ExampleWidget"
        ),
        .executableTarget(
            name: "CorniceApp",
            dependencies: ["CorniceCore", "CorniceHost", "ExampleWidgetWidget"]
        ),
        .testTarget(name: "CorniceCoreTests", dependencies: ["CorniceCore"]),
        .testTarget(name: "CorniceKitTests", dependencies: ["CorniceKit", "ExampleWidgetWidget"]),
        .testTarget(name: "CorniceHostTests", dependencies: ["CorniceHost", "CorniceKit"]),
    ]
)
