import CoreKit
import CoreUI
import Shell
import SwiftUI

/// One terminal in the list (Ahmed, 2026-11-21: "should be list not cards"): its name, where it runs, the last line of its
/// screen, and how long ago. Hover or selection shows Open (⏎) and Close (⌫). The screen line is read by the Core about every
/// three seconds while the row is on screen (once under Reduce Motion); a terminal the Core says is gone leaves the list.
struct TerminalRow: View {
    let model: TerminalsModel
    let item: TerminalItem
    let thisMac: Bool
    var index = 0
    @State private var hovering = false
    @State private var shown = false
    /// The last line the Core read from the screen (`GET /terminals/{id}/tail`); nil until the first answer.
    @State private var line: String?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    var body: some View {
        let selected = model.selected == item.id
        let name = model.shell.tabNames["terminal-\(item.id)"] ?? model.name(of: item.runner)
        HStack(spacing: Space.s3) {
            Image(systemName: "terminal").coreFont(size: MacTextSize.headline)
                .foregroundStyle(GlassInk.secondary).frame(width: Space.s5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                    MachineChip(real: thisMac)
                    RanOnChip(model.shell.hardwareDeck.jobByTerminal[item.id])
                }
                Text(subtitle).font(.system(size: 11, design: .monospaced)).foregroundStyle(GlassInk.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: Space.s2)
            Text(item.isEnded ? "ended" : ago(item.createdAt)).coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary).lineLimit(1).fixedSize()
            actions.opacity(hovering || selected ? 1 : 0).allowsHitTesting(hovering || selected)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(minHeight: MacSize.controlLg + Space.s4)
        .foregroundStyle(GlassInk.primary)
        .background(
            selected ? palette.navActive : hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.row)
        )
        .opacity(item.isEnded ? 0.7 : 1)
        .contentShape(coreShape(Radius.row))
        .onTapGesture(count: 2) { TileAction.run(.open, item.id, model) }
        .onTapGesture { withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { model.selected = item.id } }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.hover), value: selected)
        .coreRise(shown, index)
        .onAppear { shown = true }
        .task(id: item.isEnded) { await poll() }
        .contextMenu {
            Button("Open") { TileAction.run(.open, item.id, model) }
            Button("Detach") { TileAction.run(.detach, item.id, model) }.disabled(model.sessions[item.id] == nil)
            Button("Running command…") { TileAction.run(.signal, item.id, model) }.disabled(item.isEnded)
            Button("Rename…") { TileAction.run(.rename, item.id, model) }
            Divider()
            Button(item.isEnded ? "Remove from List" : "Close Terminal…", role: .destructive) {
                TileAction.run(.end, item.id, model)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name), \(thisMac ? "real shell on this Mac" : "sandbox"), \(item.isEnded ? "ended" : "open")"
        )
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { TileAction.run(.open, item.id, model) }
    }

    /// What it is doing: the last line of its screen; how it ended; or its prompt before the first answer.
    private var subtitle: String {
        if item.isEnded {
            if item.hostLost { return "Ended: its machine went away" }
            if let s = item.exitSignal { return "Ended by \(s)" }
            return "Ended · exit \(item.exitCode ?? 0)"
        }
        return line ?? "\(model.name(of: item.runner)) ~ $"
    }

    private func poll() async {
        guard !item.isEnded else { return }
        // Staggered, so a full list does not ask all at once.
        try? await Task.sleep(for: .milliseconds(120 * min(index, 10)))
        while !Task.isCancelled {
            var wait = 3.0
            do {
                let rows = try await model.service.tail(item.id, lines: 5)
                if let last = rows.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { line = last }
            } catch  where TerminalItem.isGone(error) {
                // Ended with `exit` and reaped: it leaves the list, and this row (and its asking) goes with it.
                return model.forget(item.id)
            } catch {
                // A locked Core answers `unlock_required`: stop asking until the person unlocks and the row comes back. A
                // rate limit says slow down.
                switch CoreError.unwrapping(error) {
                case .http(_, "unlock_required", _)?, .unlockRequired?: return
                case .rateLimited(let after)?: wait = max(after ?? 30, 30)
                default: break
                }
            }
            if reduce { return }
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private var actions: some View {
        HStack(spacing: Space.s1) {
            Button("Open") { TileAction.run(.open, item.id, model) }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).environment(\.coreKeycap, "⏎")
                .help("Open this terminal next to the list (⏎)")
            Button(item.isEnded ? "Remove" : "Close") { TileAction.run(.end, item.id, model) }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).environment(\.coreKeycap, "⌫")
                .help(item.isEnded ? "Remove this ended terminal from the list (⌫)" : "Close this terminal (⌫)")
        }
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
