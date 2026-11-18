// swift-tools-version: 6.0
// The native Design canvas (V3-02, plan T3/T4): a Metal view drawn by the Rust engine (`DesignEngine`, AinkradCore
// `modules/design/ffi`). Its own package so the 150 MB engine library is linked only by the app and this package's tests,
// never by `Features`: Design reaches the canvas through `DesignModel.canvas`, which the app sets.
// `Vendor/DesignEngine.xcframework` is git-ignored: `scripts/sync-engine.sh` puts it there, checked against
// `scripts/engine.pin` (the AinkradCore commit it came from and its SHA256SUMS).
import PackageDescription

let package = Package(
    name: "DesignCanvas",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DesignCanvas", targets: ["DesignCanvas"])],
    targets: [
        .binaryTarget(name: "DesignEngine", path: "Vendor/DesignEngine.xcframework"),
        .target(
            name: "DesignCanvas",
            dependencies: ["DesignEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            // Skia inside the static library is C++ and draws with Metal and CoreText.
            linkerSettings: [
                .linkedLibrary("c++"), .linkedFramework("Metal"), .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"), .linkedFramework("CoreGraphics"), .linkedFramework("ApplicationServices"),
            ]),
        .testTarget(name: "DesignCanvasTests", dependencies: ["DesignCanvas"]),
    ]
)
