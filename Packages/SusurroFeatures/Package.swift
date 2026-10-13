// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroFeatures",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroFeatures", targets: ["Presentation", "Composition"])
    ],
    dependencies: [
        .package(path: "../SusurroCore"),
        .package(path: "../SusurroPlatform"),
        .package(path: "../SusurroInference"),
    ],
    targets: [
        .target(
            name: "Presentation",
            dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]
        ),
        .target(
            name: "Composition",
            dependencies: [
                "Presentation",
                .product(name: "SusurroCore", package: "SusurroCore"),
                // The preview environment runs on the fakes. They are small, and the live environment never touches them.
                .product(name: "CoreTestSupport", package: "SusurroCore"),
                .product(name: "SusurroPlatform", package: "SusurroPlatform"),
                .product(name: "SusurroInference", package: "SusurroInference"),
            ]
        ),
        .testTarget(
            name: "PresentationTests",
            dependencies: [
                "Presentation",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
        .testTarget(
            name: "CompositionTests",
            dependencies: [
                "Composition",
                "Presentation",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
