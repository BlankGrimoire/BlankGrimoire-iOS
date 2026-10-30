// swift-tools-version: 6.0
// SPDX-License-Identifier: MPL-2.0

import PackageDescription

let package = Package(
    name: "ReaderCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ReaderCore",
            targets: ["ReaderCore"]
        ),
    ],
    dependencies: [
        // SwiftSoup for HTML parsing (native bridge implementation)
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "ReaderCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            path: "Sources/ReaderCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .define("DEBUG", .when(configuration: .debug)),
                .unsafeFlags(["-enable-bare-slash-regex"]),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "ReaderCoreTests",
            dependencies: ["ReaderCore"],
            path: "Tests/ReaderCoreTests",
            swiftSettings: [
                .unsafeFlags(["-Xlinker", "-no_application_extension"])
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-no_application_extension"])
            ]
        ),
    ]
)