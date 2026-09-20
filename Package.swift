// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "pwm-explore",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "pwmctl", targets: ["pwmctl"]),
        .library(name: "PWMKit", targets: ["PWMKit"]),
    ],
    targets: [
        .target(name: "PWMKit"),
        .executableTarget(name: "pwmctl", dependencies: ["PWMKit"]),
        .testTarget(name: "PWMKitTests", dependencies: ["PWMKit"]),
    ]
)
