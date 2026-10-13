// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroCore", targets: ["Domain"]),
        .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "CoreTestSupport", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
    ],
    swiftLanguageModes: [.v6]
)
