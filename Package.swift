// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Wamadu",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Wamadu", targets: ["Wamadu"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0")
    ],
    targets: [
        .target(name: "WamaduCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "Wamadu", dependencies: ["WamaduCore"], resources: [.process("Resources")]),
        .testTarget(
            name: "WamaduCoreTests",
            dependencies: ["WamaduCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "WamaduTests", dependencies: ["Wamadu", "WamaduCore"]),
    ]
)
