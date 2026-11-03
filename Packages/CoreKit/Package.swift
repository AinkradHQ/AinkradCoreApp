// swift-tools-version: 6.0
// CoreKit (E5-02): the only module that talks to the Ainkrad Core server. Keys, signed requests, sessions, pairing, step-up, events.
import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CoreKit", targets: ["CoreKit"])],
    dependencies: [
        .package(path: "../AinkradClient"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.13.3"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.2.0"),
    ],
    targets: [
        .target(
            name: "CoreKit",
            dependencies: [
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
        ),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
