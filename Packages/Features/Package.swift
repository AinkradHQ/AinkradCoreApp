// swift-tools-version: 6.0
// Feature modules of the Mac client. `Shell` (E5-03) is the app shell: window content, Home, launcher, bell, panes, Settings.
import PackageDescription

let package = Package(
    name: "Features",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Shell", targets: ["Shell"]), .library(name: "Pairing", targets: ["Pairing"])],
    dependencies: [
        .package(path: "../CoreUI"), .package(path: "../CoreKit"), .package(path: "../AinkradClient"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.13.3"),
    ],
    targets: [
        .target(
            name: "Shell", dependencies: [.product(name: "CoreUI", package: "CoreUI")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Pairing",
            dependencies: [
                "Shell", .product(name: "CoreUI", package: "CoreUI"), .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShellTests", dependencies: ["Shell"]),
        .testTarget(name: "PairingTests", dependencies: ["Pairing", .product(name: "CoreKit", package: "CoreKit")]),
    ]
)
