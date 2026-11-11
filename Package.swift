// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AulaWheel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AulaWheel", targets: ["AulaWheel"]),
    ],
    targets: [
        .target(name: "AulaWheelCore"),
        .executableTarget(
            name: "AulaWheel",
            dependencies: ["AulaWheelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "AulaWheelCoreTests", dependencies: ["AulaWheelCore"]),
    ]
)
