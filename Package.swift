// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Shaw",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Shaw", targets: ["Shaw"]),
        .library(name: "ShawCore", targets: ["ShawCore"]),
    ],
    targets: [
        .target(
            name: "ShawCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(name: "Shaw", dependencies: ["ShawCore"]),
        .testTarget(name: "ShawCoreTests", dependencies: ["ShawCore"]),
    ]
)
