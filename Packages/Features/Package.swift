// swift-tools-version: 6.0
// Feature modules of the Mac client. `Shell` (E5-03) is the app shell: window content, Home, launcher, bell, panes, Settings.
import PackageDescription

let package = Package(
    name: "Features",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Shell", targets: ["Shell"]), .library(name: "Pairing", targets: ["Pairing"]),
        .library(name: "Terminals", targets: ["Terminals"]), .library(name: "Admin", targets: ["Admin"]),
        .library(name: "Accounts", targets: ["Accounts"]), .library(name: "Agents", targets: ["Agents"]),
        .library(name: "Brain", targets: ["Brain"]), .library(name: "BrainImport", targets: ["BrainImport"]),
        .library(name: "Projects", targets: ["Projects"]), .library(name: "Leyline", targets: ["Leyline"]),
        .library(name: "Design", targets: ["Design"]),
        .library(name: "LoreEditor", targets: ["LoreEditor"]), .library(name: "Lore", targets: ["Lore"]),
        .library(name: "LoreImport", targets: ["LoreImport"]),
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
            name: "Shell",
            dependencies: [.product(name: "CoreUI", package: "CoreUI"), .product(name: "CoreKit", package: "CoreKit")],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Agents",
            dependencies: [
                "Shell", .product(name: "CoreUI", package: "CoreUI"), .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Terminals",
            dependencies: [
                "Shell", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Admin",
            dependencies: [
                "Shell", .product(name: "CoreUI", package: "CoreUI"), .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Accounts",
            dependencies: [
                "Shell", "Admin", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Projects",
            dependencies: [
                "Shell", "Admin", "Brain", "LoreImport", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Leyline",
            dependencies: [
                "Shell", "Admin", "Projects", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Design",
            dependencies: [
                "Shell", "Admin", "Projects", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Brain",
            dependencies: ["Shell", "Admin", "BrainImport", .product(name: "CoreUI", package: "CoreUI")],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        // The Mac-side collectors of the Brain import (E3): pure Foundation, no UI, no Core client.
        .target(name: "BrainImport", swiftSettings: [.swiftLanguageMode(.v6)]),
        // The Lore note editor (R6-02): TextKit 2, Markdown as the document, CoreUI only, no Core client.
        .target(
            name: "LoreEditor", dependencies: [.product(name: "CoreUI", package: "CoreUI")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        // Importing notes into Lore (R4-02): from a project's repo copy on the Core, or from Markdown files and zips.
        .target(
            name: "LoreImport",
            dependencies: [
                "Shell", "Admin", "BrainImport", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        // The Lore space (R6-01): today's note, autosave, remote fold-in, local drafts.
        .target(
            name: "Lore",
            dependencies: [
                "Shell", "Admin", "LoreEditor", "LoreImport", .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "Pairing",
            dependencies: [
                "Shell", "Agents", "Terminals", "Admin", "Accounts", "Brain", "BrainImport", "Projects", "Leyline",
                "Design", "Lore",
                .product(name: "CoreUI", package: "CoreUI"),
                .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShellTests", dependencies: ["Shell", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(
            name: "TerminalsTests",
            dependencies: ["Terminals", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(name: "AdminTests", dependencies: ["Admin", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(
            name: "AccountsTests",
            dependencies: [
                "Accounts", .product(name: "CoreKit", package: "CoreKit"),
                .product(name: "AinkradClient", package: "AinkradClient"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]),
        .testTarget(
            name: "AgentsTests", dependencies: ["Agents", "Shell", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(
            name: "ProjectsTests",
            dependencies: ["Projects", "Shell", "Admin", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(
            name: "LeylineTests",
            dependencies: ["Leyline", "Shell", "Admin", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(
            name: "DesignTests",
            dependencies: ["Design", "Projects", "Shell", "Admin", .product(name: "CoreKit", package: "CoreKit")],
            // The hostile mockup package of V3-07: pages that try to reach the network, the app and the outside.
            resources: [.copy("Fixtures")]),
        .testTarget(name: "BrainTests", dependencies: ["Brain", "BrainImport", "Shell", "Admin"]),
        .testTarget(name: "BrainImportTests", dependencies: ["BrainImport"]),
        .testTarget(
            name: "LoreImportTests",
            dependencies: ["LoreImport", "Shell", "Admin", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(name: "LoreEditorTests", dependencies: ["LoreEditor"]),
        .testTarget(
            name: "LoreTests", dependencies: ["Lore", "Shell", "Admin", .product(name: "CoreKit", package: "CoreKit")]),
        .testTarget(name: "PairingTests", dependencies: ["Pairing", .product(name: "CoreKit", package: "CoreKit")]),
    ]
)
