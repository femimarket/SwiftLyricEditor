// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "LyricEditor",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LyricEditor",
            targets: ["LyricEditor"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/femimarket/swiftapi", branch: "main"),
        .package(url: "https://github.com/atelier-socle/swift-audio-marker", from: "0.1.1"),
    ],
    targets: [
        .target(
            name: "LyricEditor",
            dependencies: [
                .product(name: "Api", package: "swiftapi"),
                .product(name: "AudioMarker", package: "swift-audio-marker"),
            ],
            path: "LyricEditor",
            exclude: [
                "LyricEditorApp.swift",
                "Assets.xcassets",
            ]
        ),
    ]
)
