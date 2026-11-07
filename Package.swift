// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ProClickMini",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ProClickMini", targets: ["ProClickMini"]),
        .executable(name: "proclick-probe", targets: ["proclick-probe"]),
    ],
    targets: [
        .target(name: "RazerBLE"),
        .target(name: "InputEngine", dependencies: ["RazerBLE"]),
        .target(name: "AppCore", dependencies: ["RazerBLE", "InputEngine"]),
        .executableTarget(name: "proclick-probe", dependencies: ["RazerBLE", "InputEngine"]),
        .executableTarget(name: "ProClickMini", dependencies: ["AppCore"]),
        .testTarget(name: "RazerBLETests", dependencies: ["RazerBLE"]),
        .testTarget(name: "InputEngineTests", dependencies: ["InputEngine"]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ]
)
