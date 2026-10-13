// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroFeatures",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroFeatures", targets: ["Presentation", "Composition"])
    ],
    targets: [
        .target(name: "Presentation"),
        .target(name: "Composition", dependencies: ["Presentation"]),
        .testTarget(name: "PresentationTests", dependencies: ["Presentation"]),
    ],
    swiftLanguageModes: [.v6]
)
