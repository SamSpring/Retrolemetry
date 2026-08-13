// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockTelemetry",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DockTelemetry", targets: ["DockTelemetry"])
    ],
    targets: [
        .executableTarget(
            name: "DockTelemetry",
            path: "Sources/DockTelemetry"
        )
    ]
)
