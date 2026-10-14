// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroInference",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroInference", targets: ["FluidAudioASR", "AppleIntelligenceCleaner"])
    ],
    dependencies: [
        .package(path: "../SusurroCore"),
        // Pinned exactly. The default NemoTextProcessing trait is off: it links a prebuilt text-normalization engine
        // that only speech synthesis and inverse text normalization use, and dictation uses neither.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        .target(
            name: "FluidAudioASR",
            dependencies: [
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .target(
            name: "AppleIntelligenceCleaner",
            dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]
        ),
        .testTarget(
            name: "AppleIntelligenceCleanerTests",
            dependencies: [
                "AppleIntelligenceCleaner",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
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
