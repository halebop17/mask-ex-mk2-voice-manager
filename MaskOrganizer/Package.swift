// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaskOrganizer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MaskCore", targets: ["MaskCore"]),
        .executable(name: "MaskOrganizer", targets: ["MaskOrganizer"]),
    ],
    targets: [
        .target(
            name: "MaskCore",
            path: "Sources/MaskCore"
        ),
        .executableTarget(
            name: "MaskOrganizer",
            dependencies: ["MaskCore"],
            path: "Sources/MaskOrganizer",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MaskCoreTests",
            dependencies: ["MaskCore"],
            path: "Tests/MaskCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
