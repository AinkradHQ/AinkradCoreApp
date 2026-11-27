import CoreUI
import SwiftUI

/// Over the blank canvas while a design waits for its first snapshot from the Core. After ~4 s without a connection it says
/// so, and once the Core could not be reached a few times it says that plainly. A canvas that could not start says why and
/// stops spinning. It never takes a click, and only fades (no movement), so Reduce Motion needs nothing more.
struct CanvasLoading: View {
    let editor: DesignEditor
    @State private var slow = false

    private var words: String {
        if editor.canvasFailed { return "The canvas could not start on this Mac. Try Reopen, or restart the app." }
        if editor.syncUnreachable { return "Can't reach the Core. Trying again…" }
        return slow ? "Reconnecting to your Core…" : "Opening the design…"
    }

    var body: some View {
        VStack(spacing: Space.s2) {
            if editor.canvasFailed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(GlassInk.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(words)
                .coreFont(size: MacTextSize.meta, weight: .medium)
                .foregroundStyle(GlassInk.secondary)
                .multilineTextAlignment(.center)
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

/// After the design has loaded and the link to the Core drops: a small, quiet line at the canvas's top edge. Editing goes on
/// (what is drawn syncs when the link is back); it never takes a click.
struct CanvasReconnecting: View {
    let editor: DesignEditor

    var body: some View {
        HStack(spacing: Space.s2) {
            ProgressView().controlSize(.mini)
            Text(editor.syncUnreachable ? "Can't reach the Core. Your changes stay here until it is back." : "Reconnecting…")
                .coreFont(size: MacTextSize.meta, weight: .medium)
                .foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s3)
        .frame(height: MacSize.controlMd + 2)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// A viewer's quiet cue at the canvas's top edge: you can look, select and copy, nothing changes.
struct CanvasViewOnly: View {
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "eye").foregroundStyle(GlassInk.secondary)
            Text("View only. You can look but not change this design.")
                .coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
        }
        .padding(.horizontal, Space.s3)
        .frame(height: MacSize.controlMd + 2)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
