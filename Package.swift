// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Retrolemetry",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Retrolemetry", targets: ["Retrolemetry"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Retrolemetry",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Retrolemetry",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "RetrolemetryTests", dependencies: ["Retrolemetry"])
    ]
)
