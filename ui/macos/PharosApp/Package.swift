// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PharosApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PharosApp", targets: ["PharosApp"])
    ],
    targets: [
        .executableTarget(
            name: "PharosApp",
            path: "Sources/PharosApp"
        )
    ]
)
