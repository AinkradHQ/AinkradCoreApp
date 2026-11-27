import CoreUI
import SwiftUI

/// Zoom stops, as Figma steps them: ⌘= goes to the next one up, ⌘- to the next one down.
enum ZoomSteps {
    static let stops: [Double] = [0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 32]

    /// The next stop beyond `z` in the direction asked (a tolerance keeps 100% from stepping to itself); the end stops stay.
    static func next(_ z: Double, up: Bool) -> Double {
        if up { return stops.first { $0 > z * 1.01 } ?? stops[stops.count - 1] }
        return stops.last { $0 < z / 1.01 } ?? stops[0]
    }

    /// `1` → "100%", `0.125` → "12.5%", `2.5` → "250%".
    static func percent(_ z: Double) -> String {
        let p = z * 100
        return p == p.rounded() || p >= 100 ? "\(Int(p.rounded()))%" : String(format: "%.1f%%", p)
    }
}

extension DesignEditor {
    func zoomStep(up: Bool) {
        guard let z = backend?.camera()?.zoom else { return }
        backend?.zoom(to: ZoomSteps.next(z, up: up))
    }
}

/// The zoom readout and its menu at the end of the canvas toolbar. The camera moves on scroll and pinch without the
/// document changing, so it is read on a slow clock instead of being observed.
struct ZoomMenu: View {
    @Bindable var editor: DesignEditor

    var body: some View {
        Menu {
            Button("Zoom in    ⌘=") { editor.perform(.zoomIn) }
            Button("Zoom out    ⌘-") { editor.perform(.zoomOut) }
            Divider()
            Button("Zoom to 100%    ⌘0") { editor.perform(.zoom100) }
            Button("Zoom to fit    ⇧1") { editor.perform(.fitAll) }
            Button("Zoom to selection    ⇧2") { editor.perform(.fitSelection) }
        } label: {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                HStack(spacing: Space.s1) {
                    Text(editor.camera().map { ZoomSteps.percent($0.zoom) } ?? "100%")
                        .coreFont(size: MacTextSize.body, weight: .medium).monospacedDigit()
                        .foregroundStyle(GlassInk.primary)
                    Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                        GlassInk.secondary)
                }
                .frame(minWidth: Space.s8 + Space.s4, minHeight: MacSize.controlLg + Space.s1)
                .padding(.horizontal, Space.s1)
                .contentShape(Rectangle())
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(ToolHover())
        .help("Zoom: in ⌘=, out ⌘-, 100% ⌘0, fit everything ⇧1, fit the selection ⇧2")
        .accessibilityLabel("Zoom")
        .accessibilityIdentifier("design-zoom")
    }
}
