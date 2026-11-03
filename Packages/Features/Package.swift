// swift-tools-version: 6.0
// Feature modules of the Mac client. `Shell` (E5-03) is the app shell: window content, Home, launcher, bell, panes, Settings.
import PackageDescription

let package = Package(
    name: "Features",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Shell", targets: ["Shell"])],
    dependencies: [.package(path: "../CoreUI")],
    targets: [
        .target(
            name: "Shell", dependencies: [.product(name: "CoreUI", package: "CoreUI")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShellTests", dependencies: ["Shell"]),
    ]
)
