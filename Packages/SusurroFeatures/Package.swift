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
        .package(path: "../SusurroUI"),
    ],
    targets: [
        .target(
            name: "Presentation",
            dependencies: [
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "SusurroUI", package: "SusurroUI"),
                .product(name: "DesignSystem", package: "SusurroUI"),
            ]
        ),
        .target(
            name: "Composition",
            dependencies: [
                "Presentation",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "DesignSystem", package: "SusurroUI"),
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
                .product(name: "SusurroUI", package: "SusurroUI"),
                .product(name: "DesignSystem", package: "SusurroUI"),
            ]
        ),
        .testTarget(
            name: "CompositionTests",
            dependencies: [
                "Composition",
                "Presentation",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
                .product(name: "DesignSystem", package: "SusurroUI"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
