// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Voily",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Voily", targets: ["Voily"]),
    ],
    targets: [
        .executableTarget(
            name: "Voily",
            path: "Sources/Voily"
        ),
    ]
)
