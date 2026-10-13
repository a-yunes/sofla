// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "LauncherCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
        .library(name: "LauncherInfrastructure", targets: ["LauncherInfrastructure"]),
        .executable(name: "LauncherBenchmarks", targets: ["LauncherBenchmarks"]),
    ],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "LauncherBenchmarks", dependencies: ["LauncherCore"]),
        .target(name: "LauncherInfrastructure", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
        .testTarget(
            name: "LauncherInfrastructureTests",
            dependencies: ["LauncherCore", "LauncherInfrastructure"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
