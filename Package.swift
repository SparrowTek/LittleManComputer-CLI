// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LittleManComputerCLI",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/SparrowTek/CoreLittleManComputer.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "LMC",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CoreLittleManComputer",
            ]
        ),
    ]
)
