// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VaultCore",
    // String form, not `.v26` — the enum case does not exist in tools-version
    // 6.0 and the manifest fails to compile. Verified against Swift 6.3.3.
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "VaultCore", targets: ["VaultCore"])
    ],
    targets: [
        .target(
            name: "VaultCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VaultCoreTests",
            dependencies: ["VaultCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
