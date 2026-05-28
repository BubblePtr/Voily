// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Voily",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VoilyCore", targets: ["VoilyCore"]),
        .executable(name: "VoilyApp", targets: ["VoilyApp"]),
    ],
    dependencies: [
        .package(path: "Vendor/Sparkle"),
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "VoilyCore",
            path: "Sources/VoilyCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "VoilyApp",
            dependencies: [
                "VoilyCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "PermissionFlow", package: "PermissionFlow"),
            ],
            path: "Sources/VoilyApp"
        ),
        .testTarget(
            name: "VoilyCoreTests",
            dependencies: ["VoilyCore"],
            path: "Tests/VoilyCoreTests"
        ),
    ]
)
