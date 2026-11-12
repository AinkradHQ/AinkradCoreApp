import CoreUI
import SwiftUI

/// Sources: every collector with its switch and its last run, in two groups. Tools whose history cannot be read yet are
/// listed without a switch. The rules that hold for every room sit under them.
struct SourcesTab: View {
    let brain: BrainModel
    let sync: SyncModel
    @State private var expanded = false

    private struct Line: Identifiable {
        let id: String
        let title: String
        let group: String
        let source: SourceWire?
    }

    var body: some View {
        let known = brain.importSources()
        let lines = self.lines(known)
        let unreadable = lines.filter { $0.source == nil }
        let mac = lines.compactMap(\.source).filter { !$0.isConnection }
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s4) {
                Text("Source").padding(.leading, Space.s8 + Space.s5)
                Spacer(minLength: Space.s3)
                Text("Items").frame(width: Space.s8 * 3.5, alignment: .trailing)
                Text("Last run").frame(width: Space.s8 * 4.5, alignment: .trailing)
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            .padding(.horizontal, Space.s3)
            SourceLine(
                name: "On this Mac", sub: "Claude Code, Codex, OpenCode, project docs, notes vault and more",
                items: mac.contains { $0.items != nil } ? mac.compactMap(\.items).reduce(0, +).formatted() : "",
                tap: { withAnimation(Motion.out(Motion.ui)) { expanded.toggle() } }
            ) {
                IconTile("terminal", hue: GlassInk.slate, size: Space.s8 - Space.s1)
            } last: {
                HStack(spacing: Space.s1) {
                    Text("\(mac.filter(\.enabled).count) of \(mac.count) on")
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").coreFont(size: MacTextSize.meta)
                }
                .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            }
            .accessibilityIdentifier("sources-mac")
            if expanded { macGroups(lines, unreadable) }
            ConnectionSources(sync: sync)
            RunnerSources(model: brain)
            let global = sync.rules.filter { $0.room == nil }
            if !global.isEmpty {
                HStack {
                    Text("Rules for every room").coreFont(size: MacTextSize.body, weight: .semibold)
                        .foregroundStyle(GlassInk.secondary).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.s3)
                    Text("Changing a rule asks for Touch ID").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary)
                }
                .padding(.horizontal, Space.s3).padding(.top, Space.s4)
                VStack(spacing: 2) { ForEach(global) { RuleRow(sync: sync, rule: $0) } }
            }
        }
        .task { await brain.candidates.loadRunners() }
        .frame(maxWidth: Space.s8 * 28, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-sources")
    }

    /// The Mac collectors, in their two groups, once "On this Mac" is open.
    @ViewBuilder private func macGroups(_ lines: [Line], _ unreadable: [Line]) -> some View {
        ForEach([SyncWords.sessionsGroup, SyncWords.notesGroup], id: \.self) { g in
            let rows = lines.filter { $0.group == g && $0.source?.isConnection != true }.enumerated()
                .sorted { (Self.rank($0.element), $0.offset) < (Self.rank($1.element), $1.offset) }.map(\.element)
            if !rows.isEmpty {
                Text(g).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s3).padding(.top, Space.s2)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 2) { ForEach(rows) { row($0) } }
            }
        }
        if !unreadable.isEmpty {
            Text(Self.unreadableNote(unreadable.map(\.title)))
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .padding(.horizontal, Space.s3).padding(.top, Space.s2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The Core's collectors in the wizard's order, then the tools this app cannot read yet.
    private func lines(_ known: [any ImportSource]) -> [Line] {
        let order = known.map(\.id)
        let rows = sync.sources.sorted {
            (order.firstIndex(of: $0.kind) ?? .max, $0.id) < (order.firstIndex(of: $1.kind) ?? .max, $1.id)
        }
        var out = rows.map {
            Line(id: $0.id, title: SyncWords.title($0.kind, known), group: SyncWords.group($0.kind), source: $0)
        }
        for s in known where s.notReadable != nil && !rows.contains(where: { $0.kind == s.id }) {
            out.append(Line(id: s.id, title: SyncWords.title(s.id, known), group: SyncWords.group(s.id), source: nil))
        }
        return out
    }

    /// Within a group: readable sources, then the tools that are not, then the Core's own collector.
    private static func rank(_ l: Line) -> Int { l.source?.isCore == true ? 2 : l.source == nil ? 1 : 0 }

    private func row(_ l: Line) -> some View {
        HStack(spacing: Space.s4) {
            if let s = l.source {
                CoreSwitch(
                    l.title, isOn: Binding(get: { s.enabled }, set: { on in Task { await sync.toggle(s, on: on) } })
                )
                .frame(width: Space.s8 + Space.s1, alignment: .leading)
            } else {
                Color.clear.frame(width: Space.s8 + Space.s1, height: 1)
            }
            Text(l.title).foregroundStyle(l.source == nil ? GlassInk.secondary : GlassInk.primary).lineLimit(1)
            Spacer(minLength: Space.s3)
            Text(last(l)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(width: Space.s8 * 4, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3)
        .frame(minHeight: Space.s8 + Space.s2)
        .modifier(BrainRowHover(enabled: l.source != nil))
        .help(l.source.map { "\($0.device)\($0.roots.isEmpty ? "" : ": " + $0.roots.joined(separator: ", "))" } ?? "")
        .accessibilityElement(children: .contain)
    }

    private func last(_ l: Line) -> String {
        guard let s = l.source else { return "Not readable yet" }
        guard s.enabled else { return "Off" }
        return SyncWords.date(s.lastRun).map { SyncWords.ago($0) } ?? "Not yet"
    }

    static func unreadableNote(_ names: [String]) -> String {
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names[0]
        return "\(list) \(names.count > 1 ? "keep their" : "keeps its") history in formats Ainkrad cannot read yet. "
            + "\(names.count > 1 ? "They switch" : "It switches") on here when \(names.count > 1 ? "they" : "it") can."
    }
}

/// The header's sync: when this Mac last synced, and Sync now.
struct SyncNowTile: View {
    let sync: SyncModel

    var body: some View {
        HStack(spacing: Space.s3) {
            if let label {
                Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            AppActionTile(
                title: sync.syncing ? "Syncing…" : "Sync now", symbol: "arrow.triangle.2.circlepath", key: "⌘R",
                hue: GlassInk.blue
            ) {
                Task { await sync.syncNow() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(sync.syncing)
            .help("Collect what is new from every source that is on (⌘R)")
        }
    }

    private var label: String? {
        if sync.syncing { return nil }
        guard let d = sync.lastSync else { return nil }
        let ago = SyncWords.ago(d)
        return ago == "Just now" ? "Synced just now" : "Last sync \(ago.lowercased())"
    }
}

/// Over the room list: a sync running, what it found, or imports waiting for review.
struct SyncBannerView: View {
    let brain: BrainModel
    let sync: SyncModel

    var body: some View {
        VStack(spacing: Space.s2) {
            if let n = sync.notice {
                CoreNotice(symbol: "exclamationmark.triangle", title: n, tone: .fail) {
                    Button("Dismiss") { sync.notice = nil }.buttonStyle(CoreButtonStyle(.plain, size: .small))
                }
            }
            banner
        }
        .animation(Motion.out(Motion.ui), value: sync.banner)
        .accessibilityIdentifier("brain-sync-banner")
    }

    @ViewBuilder private var banner: some View {
        let b = sync.banner
        let words = SyncWords.banner(b)
        switch b {
        case .none: EmptyView()
        case .syncing(let source, let at, let total):
            CoreNotice(symbol: "arrow.triangle.2.circlepath", title: words.title, tone: .run) {
                VStack(alignment: .trailing, spacing: Space.s1) {
                    Text([source, "\(min(at + 1, total)) of \(total)"].compactMap { $0 }.joined(separator: " · "))
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                    CoreMeter(total == 0 ? 0 : Double(at) / Double(total), label: "Sync progress")
                        .frame(width: Space.s8 * 8)
                }
            }
        case .synced(_, _, _, let review):
            CoreNotice(symbol: "checkmark", title: words.title, text: words.text, tone: .done) {
                HStack(spacing: Space.s2) {
                    if review > 0, let run = sync.review.first {
                        Button("Review \(review)") { Task { await brain.openReview(run) } }
                            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    }
                    dismiss
                }
            }
        case .nothingNew, .message:
            CoreNotice(symbol: "checkmark", title: words.title, text: words.text, tone: .done) { dismiss }
        case .waiting:
            CoreNotice(symbol: "tray", title: words.title, text: words.text, tone: .warn) {
                if let run = sync.review.first {
                    Button("Review") { Task { await brain.openReview(run) } }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        }
    }

    private var dismiss: some View {
        Button("Dismiss") { sync.dismissOutcome() }.buttonStyle(CoreButtonStyle(.plain, size: .small))
    }
}
