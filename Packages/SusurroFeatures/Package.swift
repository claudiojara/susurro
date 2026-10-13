// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroFeatures",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroFeatures", targets: ["Presentation", "Composition"])
    ],
    dependencies: [
        .package(path: "../SusurroCore")
    ],
    targets: [
        .target(
            name: "Presentation",
            dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]
        ),
        .target(name: "Composition", dependencies: ["Presentation"]),
        .testTarget(
            name: "PresentationTests",
            dependencies: [
                "Presentation",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
