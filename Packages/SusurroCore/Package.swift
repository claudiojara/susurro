// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroCore", targets: ["Domain", "Activation", "Pipeline"]),
        .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Activation", dependencies: ["Domain"]),
        .target(name: "Pipeline", dependencies: ["Domain", "Activation"]),
        .target(name: "CoreTestSupport", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "CoreTestSupportTests", dependencies: ["CoreTestSupport", "Domain"]),
        .testTarget(name: "ActivationTests", dependencies: ["Activation", "Domain"]),
        .testTarget(name: "PipelineTests", dependencies: ["Pipeline", "Activation", "Domain", "CoreTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
