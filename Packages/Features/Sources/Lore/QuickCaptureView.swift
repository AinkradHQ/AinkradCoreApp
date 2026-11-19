import AppKit
import CoreUI
import SwiftUI

/// The quick capture card: what Return does and when, the text, the advanced line, and the two actions.
struct QuickCaptureView: View {
    @Bindable var model: QuickCapture
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Label(
                model.advanced ? "New note" : "Today's note, under \(model.stamp)",
                systemImage: model.advanced ? "doc.badge.plus" : "text.book.closed"
            )
            .coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            CoreTextArea(
                nil, placeholder: model.advanced ? "Write the new note" : "Add to today's note", text: $model.text,
                error: model.error, size: MacTextSize.title, minHeight: Space.s8 * 2, maxHeight: Space.s8 * 4,
                autofocus: true, focus: $focused)
            if model.advanced {
                CoreSelect("Project", selection: $model.project, options: model.projects)
                    .help("Where the new note goes")
            }
            HStack(spacing: Space.s2) {
                Spacer()
                Button(model.advanced ? "Back to Today" : "New Note…") { model.toggleAdvanced() }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .environment(\.coreKeycap, "⌘↵")
                    .help(model.advanced ? "Add to today's note instead (⌘↵)" : "Make a new note in a project (⌘↵)")
                Button(model.advanced ? "Create Note" : "Add to Today") { Task { await model.submit() } }
                    .buttonStyle(CoreButtonStyle(.prominent))
                    .environment(\.coreKeycap, "↵")
                    .disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(model.advanced ? "Create the note (↵)" : "Add the text to today's note (↵)")
            }
        }
        .frame(width: Space.s8 * 15 - Space.s4 * 2, alignment: .leading)
        .corePanel(radius: Radius.pane)
        .padding(Space.s6)  // room for the frame's shadow inside the panel
        // One panel size (room for the project menu below the card); the card hugs the top. Transparent parts let
        // clicks through.
        .frame(width: CapturePanel.size.width, height: CapturePanel.size.height, alignment: .top)
        .foregroundStyle(GlassInk.primary)
        .coreTheme()
        .onChange(of: model.opens, initial: true) { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick capture")
    }
}

/// Settings, Apps, Lore: the one Lore setting, the quick capture shortcut.
struct LoreSettingsSection: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var capture: QuickCapture

    var body: some View {
        GlassSection(
            "Quick capture", sub: "A small panel over any app. Return adds to today's note.",
            symbol: "square.and.pencil", hue: GlassInk.accent(paneAccent)
        ) {
            ShortcutField(shortcut: $capture.shortcut)
        } content: {
            Text(status).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if capture.shortcut != .standard {
                Button("Use \(CaptureShortcut.standard.keys)") { capture.shortcut = .standard }
                    .buttonStyle(CoreButtonStyle(.secondary))
            }
        }
        .foregroundStyle(GlassInk.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: String {
        let inApp = "Inside Ainkrad, \(CaptureShortcut.standard.keys) always opens it."
        switch capture.hold {
        case .chosen: return "\(capture.shortcut.keys) works in every app. \(inApp)"
        case .fallback:
            return "\(capture.shortcut.keys) is taken by another app, so \(CaptureShortcut.fallback.keys) opens "
                + "quick capture. \(inApp)"
        case .taken: return "That shortcut is taken by another app. \(inApp)"
        }
    }
}

/// Click, then press the new keys (⌘, ⌥ or ⌃ with a key). Esc cancels.
// TODO(design-system): proposal CoreShortcutField — a shortcut recorder; a secondary CoreButton with the keys stands in.
private struct ShortcutField: View {
    @Binding var shortcut: CaptureShortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type a Shortcut" : shortcut.keys) { recording ? stop() : start() }
            .buttonStyle(CoreButtonStyle(.secondary))
            .help(
                recording ? "Press the new keys, or Esc to keep \(shortcut.keys)" : "Change the quick capture shortcut"
            )
            .accessibilityLabel("Quick capture shortcut")
            .accessibilityValue(shortcut.keys)
            .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            MainActor.assumeIsolated {
                if e.keyCode == 53 {
                    stop()
                } else if let s = CaptureShortcut(event: e) {
                    shortcut = s
                    stop()
                }
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
