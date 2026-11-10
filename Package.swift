// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Maloche",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Maloche", targets: ["Maloche"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0")
    ],
    targets: [
        .target(name: "MalocheCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "Maloche", dependencies: ["MalocheCore"], resources: [.process("Resources")]),
        .testTarget(
            name: "MalocheCoreTests",
            dependencies: ["MalocheCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "MalocheTests", dependencies: ["Maloche", "MalocheCore"]),
    ]
)
