// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LittleManComputerCLI",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(path: "../CoreLittleManComputer"),
        .package(url: "https://github.com/vapor/console-kit", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "LMC",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ConsoleKitTerminal", package: "console-kit"),
                "CoreLittleManComputer",
            ]
        ),
        .testTarget(
            name: "LMCTests",
            dependencies: [
                "LMC",
                "CoreLittleManComputer"
            ]
        ),
    ]
)
