// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroInference",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroInference", targets: ["FluidAudioASR", "CloudProviders", "LocalWhisper"])
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
        .target(name: "CloudProviders", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .target(name: "LocalWhisper", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        // A web server inside the test process, so that no test reaches a network. Only test targets use it.
        .target(name: "InferenceTestSupport"),
        .testTarget(
            name: "CloudProvidersTests",
            dependencies: [
                "CloudProviders",
                "InferenceTestSupport",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
        .testTarget(
            name: "LocalWhisperTests",
            dependencies: [
                "LocalWhisper",
                "InferenceTestSupport",
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
