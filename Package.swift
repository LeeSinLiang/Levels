// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Levels",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "Levels", targets: ["Levels"])],
    targets: [
        .target(name: "MixerDSP", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(name: "MixerCore", dependencies: ["MixerDSP"]),
        .executableTarget(name: "Levels", dependencies: ["MixerCore", "MixerDSP"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "MixerChecks", dependencies: ["MixerCore", "MixerDSP"], path: "Tests/MixerCoreTests")
    ]
)
