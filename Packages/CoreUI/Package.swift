// swift-tools-version: 6.0
// The Ainkrad Core design system (E5-01). `Tokens.swift` is generated: run scripts/sync-tokens.sh, never edit it.
import PackageDescription

let package = Package(
    name: "CoreUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CoreUI", targets: ["CoreUI"])],
    targets: [
        .target(
            name: "CoreUI", resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CoreUITests", dependencies: ["CoreUI"]),
    ]
)
