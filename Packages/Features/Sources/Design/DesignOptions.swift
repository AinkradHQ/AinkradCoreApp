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
    static func nodeID() -> String {
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
                "props": .object(["w": .number(s.w), "h": .number(s.h)]),
            ],
        ]
    }
}

struct DesignOptionsTab: View {
    let options = DesignOptions.options

    var body: some View {
        GlassSection("Canvas", sub: "How a design is laid out and where it starts", symbol: "square.dashed", hue: GlassInk.blue)
        {
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
