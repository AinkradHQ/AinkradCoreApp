import AppKit
import CoreUI
import SwiftUI

/// The quick capture bar (mockup 19): a note tile and the text, which grows with it; the destination chip, the word
/// count and the keys. After Return it says where the note went, with Undo.
struct QuickCaptureView: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var model: QuickCapture
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let saved = model.saved { done(saved) } else { editing }
        }
        .frame(width: Space.s8 * 20 - Space.s4 * 2, alignment: .leading)
        .corePanel(radius: Radius.pane)
        .padding(Space.s6)  // room for the frame's shadow inside the panel
        // One panel size (room for the destination menu below the bar); the bar hugs the top. Transparent parts let
        // clicks through.
        .frame(width: CapturePanel.size.width, height: CapturePanel.size.height, alignment: .top)
        .foregroundStyle(GlassInk.primary)
        .coreTheme()
        .animation(reduceMotion ? nil : Motion.out(Motion.ui), value: model.saved)
        .onChange(of: model.opens, initial: true) { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick capture")
    }

    @ViewBuilder private var editing: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "note.text").coreFont(size: MacTextSize.title).foregroundStyle(
                GlassInk.accent(paneAccent)
            )
            .frame(width: MacSize.controlLg, height: MacSize.controlLg)
            .background(GlassInk.accent(paneAccent).opacity(0.16), in: coreShape(Radius.control)).accessibilityHidden(
                true)
            CoreTextArea(
                nil, placeholder: "Write a note…", text: $model.text, error: model.error, size: MacTextSize.title,
                minHeight: MacSize.controlLg, maxHeight: Space.s8 * 7.5, autofocus: true, focus: $focused)
        }
        HStack(spacing: Space.s2) {
            CoreDropdown(items: items) {
                HStack(spacing: Space.s1) {
                    Image(systemName: model.destination.symbol).coreFont(size: MacTextSize.meta + 1)
                    Text(model.destination.name).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").coreFont(size: MacTextSize.meta - 1)
                        .foregroundStyle(GlassInk.secondary)
                }
                .padding(.horizontal, Space.s2).frame(minHeight: MacSize.controlMd)
                .background(GlassInk.well, in: coreShape(Radius.control))
            }
            .help("Where this note goes")
            .accessibilityLabel("Destination: \(model.destination.name)")
            if words > 0 {
                Text("\(words) \(words == 1 ? "word" : "words")").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer()
            key("⏎", "Save")
            key("⎋", "Cancel")
        }
        .padding(.leading, MacSize.controlLg + Space.s3)
    }

    private func done(_ s: QuickSaved) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark").coreFont(size: MacTextSize.title, weight: .semibold)
                .foregroundStyle(GlassInk.green).frame(width: MacSize.controlLg, height: MacSize.controlLg)
                .background(GlassInk.green.opacity(0.16), in: coreShape(Radius.control)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Saved to \(s.destination)").coreFont(size: MacTextSize.body + 1, weight: .semibold)
                Text(s.time).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Spacer()
            Button {
                let body = model.lastBody
                Task { await model.undo(body) }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
    }

    private var words: Int { model.text.split(whereSeparator: { $0.isWhitespace }).count }

    private var items: [CoreDropdownItem] {
        model.destinations.map { d in
            CoreDropdownItem(d.name, symbol: d.symbol, checked: d == model.destination) {
                model.destination = d
                focused = true
            }
        }
    }

    private func key(_ k: String, _ label: String) -> some View {
        HStack(spacing: Space.s1) {
            Text(k).coreFont(size: MacTextSize.meta, weight: .medium).padding(.horizontal, Space.s1 + 2)
                .frame(minHeight: MacSize.chip).background(GlassInk.well, in: coreShape(Radius.chip))
            Text(label)
        }
        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).accessibilityElement(children: .combine)
    }
}

/// Settings, Apps, Lore: the one Lore setting, the quick capture shortcut.
struct LoreSettingsSection: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var capture: QuickCapture

    var body: some View {
        GlassSection(
            "Quick capture", sub: "A small bar over any app. Return saves the note.",
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
