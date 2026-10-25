// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MemobirdService", platforms: [.macOS(.v14)],
    products: [
        .executable(name: "memobird", targets: ["MemobirdCLI"]),
        .executable(name: "MemobirdService", targets: ["MemobirdService"]),
        .executable(name: "MemobirdRenderer", targets: ["MemobirdRenderer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.28.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MemobirdCore", dependencies: ["CSQLite"]),
        .target(name: "MemobirdTransport", dependencies: ["MemobirdCore"]),
        .executableTarget(
            name: "MemobirdService",
            dependencies: [
                "MemobirdCore", "MemobirdTransport", .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "NIOPosix", package: "swift-nio"), .product(name: "Logging", package: "swift-log"),
            ]),
        .executableTarget(name: "MemobirdRenderer", dependencies: ["MemobirdCore"], resources: [.process("Resources")]),
        .executableTarget(
            name: "MemobirdCLI",
            dependencies: ["MemobirdCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "MemobirdCoreTests", dependencies: ["MemobirdCore"]),
    ]
)
