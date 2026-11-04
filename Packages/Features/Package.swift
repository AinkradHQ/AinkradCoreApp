// swift-tools-version: 6.0
// Feature modules of the Mac client. `Shell` (E5-03) is the app shell: window content, Home, launcher, bell, panes, Settings.
import PackageDescription

let package = Package(
    name: "Features",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Shell", targets: ["Shell"]), .library(name: "Pairing", targets: ["Pairing"]),
        .library(name: "Terminals", targets: ["Terminals"]),
    ],
    dependencies: [
        .package(path: "../CoreUI"), .package(path: "../CoreKit"), .package(path: "../AinkradClient"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.13.3"),
        // The vendored fork (no reflow on resize), pinned to a commit of branch `ainkrad-no-reflow`.
        .package(
            url: "https://github.com/AhmedMElhalaby/SwiftTerm", revision: "e44352494333686a5de418f85f7927b81c6a9fbe"),
    ],
    targets: [
        .target(
            name: "Shell", dependencies: [.product(name: "CoreUI", package: "CoreUI")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Terminals",
            dependencies: [
                "Shell", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Pairing",
            dependencies: [
                "Shell", "Terminals", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShellTests", dependencies: ["Shell"]),
        .testTarget(
            name: "TerminalsTests",
            dependencies: ["Terminals", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(name: "PairingTests", dependencies: ["Pairing", .product(name: "CoreKit", package: "CoreKit")]),
    ]
)
