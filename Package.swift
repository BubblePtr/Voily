// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Voily",
    platforms: [
        .macOS(.v26),
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
