// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VectaEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VectaEngine", targets: ["VectaEngine"])
    ],
    targets: [
        .target(
            name: "VectaEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VectaEngineTests",
            dependencies: ["VectaEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
