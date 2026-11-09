// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Wamadu",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Wamadu", targets: ["Wamadu"])
    ],
    targets: [
        .target(name: "WamaduCore"),
        .executableTarget(name: "Wamadu", dependencies: ["WamaduCore"]),
        .testTarget(name: "WamaduCoreTests", dependencies: ["WamaduCore"]),
    ]
)
