import CoreUI
import SwiftUI

/// Over the blank canvas while a design waits for its first snapshot from the Core. After ~4 s without a connection it says
/// so. It never takes a click, and only fades (no movement), so Reduce Motion needs nothing more.
struct CanvasLoading: View {
    let editor: DesignEditor
    @State private var slow = false

    var body: some View {
        VStack(spacing: Space.s2) {
            ProgressView().controlSize(.small)
            Text(slow ? "Reconnecting to your Core…" : "Opening the design…")
                .coreFont(size: MacTextSize.meta, weight: .medium)
                .foregroundStyle(GlassInk.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .task(id: editor.syncConnected) {
            guard !editor.syncConnected else { return slow = false }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { slow = true }
        }
    }
}
