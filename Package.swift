// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Reclaim",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReclaimCore", targets: ["ReclaimCore"]),
        .executable(name: "reclaim", targets: ["ReclaimCLI"]),
    ],
    targets: [
        .target(name: "ReclaimCore"),
        .executableTarget(name: "ReclaimCLI", dependencies: ["ReclaimCore"]),
        .testTarget(name: "ReclaimCoreTests", dependencies: ["ReclaimCore"]),
    ]
)
