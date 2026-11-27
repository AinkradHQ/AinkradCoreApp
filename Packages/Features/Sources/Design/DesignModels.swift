import Foundation

/// A design document in the Core: a design (app screens), a design system, or an HTML mockup package.
struct DesignDoc: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case design, system, mockup }
    let id: String
    var kind: Kind
    var name: String
    var system: String?
    var projects: [String]
    var aiPaused: Bool
    var createdBy: String
    var updatedAt: Date?
}

/// A file in the library. Only `ok` files are served; a font or Icon Composer file stays `pending` until the design helper
/// (V6-01) has checked it, and the app never loads a font file itself.
struct DesignAsset: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case image, icon, logo, font, pdf, other
        case iconComposer = "icon_composer"
    }
    enum Check: String, Sendable { case ok, pending, refused }
    var id: String { sha }
    let sha: String
    var kind: Kind
    var name: String
    var contentType: String
    var size: Int64
    var check: Check
    var tags: [String]
    var projects: [String]
    var createdAt: Date?

    /// Whether the app may fetch its bytes: checked, and never a font (fonts are only ever loaded by the helper).
    var loadable: Bool { check == .ok && kind != .font }

    /// The file name a drag to Finder writes.
    var fileName: String {
        let ext: String =
            switch contentType {
            case "image/png": "png"
            case "image/jpeg": "jpg"
            case "image/gif": "gif"
            case "image/webp": "webp"
            case "image/svg+xml": "svg"
            case "application/pdf": "pdf"
            case "application/zip": kind == .iconComposer ? "icon.zip" : "zip"
            default: ""
            }
        let base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return ext.isEmpty || base.lowercased().hasSuffix(".\(ext)") ? base : "\(base).\(ext)"
    }
}

/// A brand kit: logos by role, its colours (`#rrggbb`) and the font assets it names. Folders are not shown in 0.9.
struct BrandKit: Identifiable, Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let sha: String
        let role: String?
    }
    let id: String
    var name: String
    var colors: [String]
    var fonts: [String]
    var items: [Item]
    var projects: [String]
    var updatedAt: Date?
}

/// One card of the home wall or a row of the project island.
enum DesignItem: Identifiable, Equatable, Sendable {
    case doc(DesignDoc)
    case asset(DesignAsset)
    case kit(BrandKit)

    var id: String {
        switch self {
        case .doc(let d): "doc:\(d.id)"
        case .asset(let a): "asset:\(a.sha)"
        case .kit(let k): "kit:\(k.id)"
        }
    }
    var name: String {
        switch self {
        case .doc(let d): d.name
        case .asset(let a): a.name
        case .kit(let k): k.name
        }
    }
    var projects: [String] {
        switch self {
        case .doc(let d): d.projects
        case .asset(let a): a.projects
        case .kit(let k): k.projects
        }
    }
    var date: Date? {
        switch self {
        case .doc(let d): d.updatedAt
        case .asset(let a): a.createdAt
        case .kit(let k): k.updatedAt
        }
    }
    var tags: [String] { if case .asset(let a) = self { a.tags } else { [] } }

    /// The category of the rail it lives in.
    var category: DesignCategory {
        switch self {
        case .doc(let d):
            switch d.kind {
            case .design: .screens
            case .system: .systems
            case .mockup: .mockups
            }
        case .kit: .brand
        case .asset(let a):
            switch a.kind {
            case .logo: .brand
            case .icon, .iconComposer: .icons
            case .font: .fonts
            case .image, .pdf, .other: .illustrations
            }
        }
    }

    /// The kind in words, for a card's second line.
    var kindWord: String {
        switch self {
        case .doc(let d):
            switch d.kind {
            case .design: "design"
            case .system: "design system"
            case .mockup: "HTML mockup"
            }
        case .kit: "brand kit"
        case .asset(let a):
            switch a.kind {
            case .image: "image"
            case .icon: "icon"
            case .logo: "logo"
            case .iconComposer: "Icon Composer"
            case .font: "font"
            case .pdf: "PDF"
            case .other: "file"
            }
        }
    }

    var symbol: String { category.symbol }
}

/// The rail of the home: everything, then one row per kind.
enum DesignCategory: String, CaseIterable, Identifiable, Sendable {
    case all, screens, brand, icons, illustrations, fonts, systems, mockups
    /// Every library file and kit at once: brand, icons, illustrations and fonts.
    case library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All designs"
        case .screens: "App screens"
        case .brand: "Brand & logos"
        case .icons: "Icons"
        case .illustrations: "Illustrations"
        case .fonts: "Fonts"
        case .systems: "Design systems"
        case .mockups: "HTML mockups"
        case .library: "Library"
        }
    }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .screens: "iphone"
        case .brand: "seal"
        case .icons: "square.grid.3x3"
        case .illustrations: "photo"
        case .fonts: "textformat"
        case .systems: "swatchpalette"
        case .mockups: "chevron.left.forwardslash.chevron.right"
        case .library: "photo.on.rectangle"
        }
    }
    /// The kinds, in the rail's order (the mockup's, with Fonts beside Illustrations).
    static let kinds: [DesignCategory] = [.screens, .brand, .icons, .illustrations, .fonts, .systems, .mockups]
    /// The library's own kinds, in the Library page's order.
    static let libraryKinds: [DesignCategory] = [.brand, .icons, .illustrations, .fonts]
    /// The header's pages, each with its key (⌘1…⌘5).
    static let pages: [DesignCategory] = [.all, .screens, .systems, .mockups, .library]
    /// The header page this category lives on: a library kind on Library.
    var page: DesignCategory { Self.libraryKinds.contains(self) ? .library : self }
    /// The header's short name.
    var short: String {
        switch self {
        case .all: "All"
        case .screens: "Designs"
        case .systems: "Systems"
        case .mockups: "Mockups"
        case .brand: "Brand"
        default: title
        }
    }
}

enum DesignLoad: Equatable {
    case notConnected, loading, ready
    case failed(String)
    /// The Core has no Design module (it answered 404).
    case absent
}

enum Ago {
    static func words(_ d: Date?, now: Date = Date()) -> String {
        guard let d else { return "" }
        if now.timeIntervalSince(d) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: now)
    }

    static func iso(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// The Core's name rule (`name_ok`): 1 to 100 characters (200 for a library file), counted as Unicode scalars, no control
/// characters (a newline included), nothing at either end.
enum DesignName {
    static func limit(_ item: DesignItem) -> Int { if case .asset = item { 200 } else { 100 } }
    /// The name as it would be sent: surrounding spaces and newlines cut.
    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func valid(_ s: String, limit: Int) -> Bool {
        let n = clean(s)
        return (1...limit).contains(n.unicodeScalars.count)
            && !n.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

enum Words {
    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}
