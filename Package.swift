// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PingMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PingMonitor", targets: ["PingMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "PingMonitor",
            path: "Sources/PingMonitor"
        )
    ]
)