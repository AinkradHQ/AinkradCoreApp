import CoreUI
import SwiftUI

/// The tool's colour on its tile: Claude in the accent blue, the others quiet (the AI Sessions list is rows now, not cards).
enum SessionTile {
    static func hue(_ harness: String) -> Color {
        switch AgentWords.harnessName(harness) {
        case "Claude": GlassInk.blue
        default: GlassInk.slate
        }
    }
}
