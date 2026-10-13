// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroInference",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroInference", targets: ["FluidAudioASR"])
    ],
    targets: [
        .target(name: "FluidAudioASR"),
        .testTarget(name: "FluidAudioASRTests", dependencies: ["FluidAudioASR"]),
    ],
    swiftLanguageModes: [.v6]
)
