// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CustomerProtectionG0",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ProtectionG0", targets: ["G0App"]),
        .executable(name: "g0-check", targets: ["G0Check"]),
        .executable(name: "g0-self-test", targets: ["G0SelfTest"])
    ],
    targets: [
        .target(name: "G0Core", swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]),
        .executableTarget(name: "G0App", dependencies: ["G0Core"]),
        .executableTarget(name: "G0Check", dependencies: ["G0Core"]),
        .executableTarget(name: "G0SelfTest", dependencies: ["G0Core"], path: "Tests/G0CoreTests")
    ],
    swiftLanguageModes: [.v6]
)
