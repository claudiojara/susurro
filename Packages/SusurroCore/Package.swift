// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroCore", targets: ["Domain", "TextShaping", "Pipeline"]),
        .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "TextShaping", dependencies: ["Domain"]),
        .target(name: "Pipeline", dependencies: ["Domain", "TextShaping"]),
        .target(name: "CoreTestSupport", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "TextShapingTests", dependencies: ["TextShaping", "Domain", "CoreTestSupport"]),
        .testTarget(name: "CoreTestSupportTests", dependencies: ["CoreTestSupport", "Domain"]),
        .testTarget(name: "PipelineTests", dependencies: ["Pipeline", "TextShaping", "Domain", "CoreTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
