// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoidaEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoidaEngine", targets: ["VoidaEngine"])
    ],
    targets: [
        .target(
            name: "VoidaEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VoidaEngineTests",
            dependencies: ["VoidaEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
