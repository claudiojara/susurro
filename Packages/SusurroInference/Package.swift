// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroInference",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroInference", targets: ["FluidAudioASR"])
    ],
    dependencies: [
        .package(path: "../SusurroCore")
    ],
    targets: [
        .target(
            name: "FluidAudioASR",
            dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]
        ),
        .testTarget(
            name: "FluidAudioASRTests",
            dependencies: [
                "FluidAudioASR",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
