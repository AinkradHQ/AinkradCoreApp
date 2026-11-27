import CoreUI
import Foundation
import SwiftUI

/// Settings, Apps, Design, Options (E2-4): snap to grid and the canvas a new design starts with. The inspector reads
/// `snap` when it writes a position or size, and `DesignModel.create` hands `starterOps` to the new design's editor.
@MainActor enum DesignOptions {
    static var options: AppOptions { .shared("design") }
    static let snapKey = "snap"
    static let canvasKey = "canvas"
    /// The grid, in points.
    static let grid = 8.0

    enum Canvas: String, CaseIterable {
        case phone, tablet, desktop
        var title: String { rawValue.capitalized }
        /// The size the words ask for ("a desktop landing page", "tablet", "mobile app"), nil when they name none. A phone
        /// word wins over a desktop one ("phone dashboard", "mobile app dashboard"); "web" and "landing page" mean desktop.
        /// Also English, Arabic, French, Spanish and German common words.
        static func named(in words: String) -> Canvas? {
            let w = words.lowercased()
            // ASCII words match whole words; other scripts match anywhere (Arabic prefixes: للموبايل).
            func has(_ list: [String]) -> Bool {
                list.contains {
                    $0.unicodeScalars.first.map(\.isASCII) == false
                        ? w.contains($0) : w.range(of: "\\b\($0)\\b", options: .regularExpression) != nil
                }
            }
            // ponytail: "handy" is also an English adjective; a word list has no way to tell, add context checks if it bites.
            if has([
                "mobile", "phone", "iphone", "android", "smartphone", "موبايل", "جوال", "هاتف", "móvil", "movil",
                "celular", "handy", "téléphone", "telephone",
            ]) {
                return .phone
            }
            if has(["tablet", "ipad", "tablette", "tableta", "تابلت", "لوحي"]) { return .tablet }
            if has([
                "desktop", "web", "website", "webpage", "web page", "landing page", "laptop", "browser", "dashboard",
                "سطح المكتب", "ويب", "موقع", "ordinateur", "site web", "escritorio", "sitio web", "página web",
                "pagina web", "computadora", "webseite", "webanwendung",
            ]) {
                return .desktop
            }
            if has(["ios"]) { return .phone }
            return nil
        }
        /// The frame's width and height in points.
        var size: (w: Double, h: Double) {
            switch self {
            case .phone: (390, 844)
            case .tablet: (820, 1180)
            case .desktop: (1440, 900)
            }
        }
    }

    static var snapOn: Bool { options.bool(snapKey, true) }
    static var canvas: Canvas { Canvas(rawValue: options.string(canvasKey, "desktop")) ?? .desktop }

    /// A position or size moved onto the grid when snapping is on; nil stays nil (a cleared field).
    static func snap(_ v: Double?, on: Bool = snapOn) -> Double? {
        guard on, let v else { return v }
        return (v / grid).rounded() * grid
    }

    /// A node id the engine accepts: `n_` and 12 characters of a-z, 2-7.
    nonisolated static func nodeID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        return "n_" + String((0..<12).map { _ in alphabet.randomElement()! })
    }

    /// A page with one frame of the chosen canvas size: what a new, empty design starts with.
    static func starterOps(_ canvas: Canvas, page: String = nodeID(), frame: String = nodeID()) -> [[String: DJSON]] {
        let s = canvas.size
        return [
            [
                "op": .string("add"), "id": .string(page), "type": .string("page"), "parent": .null,
                "order": .string("a"), "name": .string("Page"),
            ],
            [
                "op": .string("add"), "id": .string(frame), "type": .string("frame"), "parent": .string(page),
                "order": .string("a"), "name": .string(canvas.title),
                "props": .object([
                    "w": .number(s.w), "h": .number(s.h),
                    // A white board: without a fill the frame is invisible on the night canvas.
                    "fill": .array([.object(["type": .string("solid"), "color": .string("#FFFFFF")])]),
                ]),
            ],
        ]
    }
}

struct DesignOptionsTab: View {
    @Environment(\.coreAccent) private var paneAccent
    let options = DesignOptions.options

    var body: some View {
        GlassSection(
            "Canvas", sub: "How a design is laid out and where it starts", symbol: "square.dashed",
            hue: GlassInk.accent(paneAccent)
        ) {
            VStack(spacing: Space.s2) {
                OptionSwitchRow(
                    "Snap to grid", sub: "Positions and sizes typed in the inspector land on an 8 pt grid",
                    symbol: "grid", isOn: options.flag(DesignOptions.snapKey, true))
                OptionSelectRow(
                    "Default canvas", sub: "The frame a new design starts with", symbol: "rectangle.dashed",
                    selection: options.text(DesignOptions.canvasKey, "desktop"),
                    options: DesignOptions.Canvas.allCases.map { CoreSelectOption($0.rawValue, $0.title) })
            }
        }
        .foregroundStyle(GlassInk.primary)
    }
}
