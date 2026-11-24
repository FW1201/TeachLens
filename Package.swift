// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TeachLens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TeachLensCore", targets: ["TeachLensCore"]),
        .executable(name: "TeachLens", targets: ["TeachLens"]),
        .executable(name: "TeachLensSelfTest", targets: ["TeachLensSelfTest"])
    ],
    targets: [
        .target(
            name: "TeachLensCore",
            path: "Sources/TeachLensCore",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "TeachLens",
            dependencies: ["TeachLensCore"],
            path: "Sources/TeachLensApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ],
            linkerSettings: [
                // Embed an Info.plist into the executable so privacy usage
                // descriptions (e.g. microphone) are present even when run as a
                // bare SwiftPM binary, allowing permission prompts without
                // crashing.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "TeachLensInfo.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "TeachLensSelfTest",
            dependencies: ["TeachLensCore"],
            path: "Sources/TeachLensSelfTest",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)