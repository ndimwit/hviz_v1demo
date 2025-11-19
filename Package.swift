// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioVisualizer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AudioVisualizer",
            targets: ["AudioVisualizer"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "AudioVisualizer",
            dependencies: [
                .product(
                    name: "ComposableArchitecture",
                    package: "swift-composable-architecture"
                ),
            ]
        ),
        .testTarget(
            name: "AudioVisualizerTests",
            dependencies: ["AudioVisualizer"],
            path: "Tests/AudioVisualizerTests"
        ),
    ]
)

