import CoreKit
import CoreUI
import SwiftUI

/// One terminal in the list (E6-3, `screens/08-terminals.html`): a live look at its screen, its name, whether it is a real
/// shell on this Mac or a sandbox, and how long ago. Hover shows Open and Close. The preview is the last lines of the screen,
/// read by the Core; under Reduce Motion it is read once when the card appears, not on a timer.
struct TerminalCard: View {
    let model: TerminalsModel
    let item: TerminalItem
    let thisMac: Bool
    var index = 0
    @State private var hovering = false
    @State private var shown = false
    /// The last rows the Core read from the screen (`GET /terminals/{id}/tail`); nil until the first answer.
    @State private var tail: [String]?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    var body: some View {
        let selected = model.selected == item.id
        let name = model.shell.tabNames["terminal-\(item.id)"] ?? model.name(of: item.runner)
        VStack(spacing: 0) {
            preview
            HStack(spacing: Space.s2) {
                Text(name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                MachineChip(real: thisMac)
                Spacer(minLength: Space.s2)
                Text(item.isEnded ? "ended" : ago(item.createdAt)).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            .padding(.horizontal, Space.s3).padding(.top, Space.s2).padding(.bottom, Space.s3)
        }
        .foregroundStyle(GlassInk.primary)
        .background(
            selected ? palette.navActive : hovering ? GlassInk.wellHover : GlassInk.well,
            in: coreShape(Radius.cardMac)
        )
        .overlay(alignment: .topTrailing) {
            if hovering || selected { actions.transition(.opacity) }
        }
        .clipShape(coreShape(Radius.cardMac))
        .opacity(item.isEnded ? 0.7 : 1)
        .contentShape(coreShape(Radius.cardMac))
        .onTapGesture(count: 2) { TileAction.run(.open, item.id, model) }
        .onTapGesture { withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { model.selected = item.id } }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.hover), value: selected)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .contextMenu {
            Button("Open") { TileAction.run(.open, item.id, model) }
            Button("Detach") { TileAction.run(.detach, item.id, model) }.disabled(model.sessions[item.id] == nil)
            Button("Running command…") { TileAction.run(.signal, item.id, model) }.disabled(item.isEnded)
            Button("Rename…") { TileAction.run(.rename, item.id, model) }
            Divider()
            Button("Close Terminal…", role: .destructive) { TileAction.run(.end, item.id, model) }
                .disabled(item.isEnded)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name), \(thisMac ? "real shell on this Mac" : "sandbox"), \(item.isEnded ? "ended" : "open")"
        )
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { TileAction.run(.open, item.id, model) }
    }

    /// The screen: last lines, bottom-aligned, fading out toward the top; always dark, in the user's terminal theme. The Core
    /// reads them (one short call, no attach, no Touch ID) about every three seconds while the card is on screen, and once
    /// under Reduce Motion. Before the first answer a card shows its prompt.
    private var preview: some View {
        let rows = tail.flatMap { $0.isEmpty ? nil : $0 }
        return lines(
            item.isEnded ? ["[exited]"] : rows ?? ["\(model.name(of: item.runner)) ~ $"],
            cursor: !item.isEnded && rows == nil
        )
        .frame(height: Space.s8 * 3 + Space.s1, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        .task(id: item.isEnded) { await poll() }
    }

    private func poll() async {
        guard !item.isEnded else { return }
        // Staggered, so a full list does not ask all at once.
        try? await Task.sleep(for: .milliseconds(120 * min(index, 10)))
        while !Task.isCancelled {
            do {
                tail = try await model.service.tail(item.id, lines: 5)
            } catch {
                // A locked Core answers `unlock_required`, and a rate limit says slow down: stop asking, and the card
                // keeps its prompt line. The list asks again when the person unlocks and the card comes back.
                if case .http(_, let code, _)? = CoreError.unwrapping(error), code == "unlock_required" { return }
            }
            if reduce { return }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func lines(_ rows: [String], cursor: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            }
            if cursor { BlockCursor(animated: !reduce) }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(GlassInk.secondary)
        .padding(.horizontal, Space.s3).padding(.top, Space.s3)
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)))
    }

    private var actions: some View {
        HStack(spacing: Space.s1) {
            Button("Open") { TileAction.run(.open, item.id, model) }
                .buttonStyle(CoreButtonStyle(.secondary)).help("Open this terminal next to the list (↩)")
            if !item.isEnded {
                Button("Close") { TileAction.run(.end, item.id, model) }
                    .buttonStyle(CoreButtonStyle(.secondary)).help("Close this terminal (⌫)")
            }
        }
        .padding(Space.s2)
    }
}

/// A block cursor that blinks; still under Reduce Motion.
private struct BlockCursor: View {
    let animated: Bool
    @State private var off = false
    var body: some View {
        coreShape(1.5).fill(GlassInk.primary).frame(width: 6, height: 12)
            .opacity(off ? 0.15 : 1)
            .coreLoop(animated ? .easeInOut(duration: 0.6).repeatForever() : nil, value: off)
            .onAppear { off = animated }
            .accessibilityHidden(true)
    }
}

/// "This Mac" (a real shell, amber: it can change your files) or "Sandbox" (blue: a safe room).
struct MachineChip: View {
    let real: Bool
    @Environment(\.coreAccent) private var paneAccent
    var body: some View {
        let hue = real ? GlassInk.amber : GlassInk.accent(paneAccent)
        Label(real ? "This Mac" : "Sandbox", systemImage: real ? "laptopcomputer" : "shield")
            .labelStyle(.titleAndIcon).coreFont(size: MacTextSize.meta, weight: .medium)
            .foregroundStyle(GlassInk.ink(hue)).lineLimit(1).fixedSize()
            .padding(.horizontal, Space.s2).frame(height: MacSize.chip)
            .background(hue.opacity(0.17), in: coreShape(Radius.chip))
            .help(
                real ? "A real shell on this Mac. It can change your files." : "A safe room. It cannot see your files.")
    }
}
