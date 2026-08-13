// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Retrolemetry",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Retrolemetry", targets: ["Retrolemetry"])
    ],
    targets: [
        .executableTarget(
            name: "Retrolemetry",
            path: "Sources/Retrolemetry"
        )
    ]
)
