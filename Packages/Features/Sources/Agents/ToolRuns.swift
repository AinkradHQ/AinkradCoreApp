import CoreUI
import SwiftUI

/// What the transcript column draws: one entry, or a run of tool steps folded into one line (Ahmed, 2026-11-15: a run of
/// near-identical tool rows was the screen's loudest noise). A run keeps its first entry's seq, so a lone tool row that
/// gains a neighbour becomes a run without the column losing its place.
enum TranscriptItem: Identifiable, Equatable {
    case one(TranscriptEntry)
    case run([TranscriptEntry])

    var id: Int64 {
        switch self {
        case .one(let e): e.seq
        case .run(let es): es[0].seq
        }
    }

    /// Two or more tool steps in a row become a run; everything else (words, cards, connection cues) stands alone.
    static func items(_ entries: [TranscriptEntry]) -> [TranscriptItem] {
        var out: [TranscriptItem] = []
        var run: [TranscriptEntry] = []
        func flush() {
            if run.count >= 2 { out.append(.run(run)) } else { out += run.map { .one($0) } }
            run = []
        }
        for e in entries {
            if ToolStep(e) != nil {
                run.append(e)
            } else {
                flush()
                out.append(.one(e))
            }
        }
        flush()
        return out
    }
}

/// One tool step, as the run's summary counts it.
struct ToolStep {
    enum Kind: CaseIterable { case read, search, edit, command, web, other }
    let kind: Kind
    /// nil while it runs.
    let ok: Bool?
    let ms: Int?

    init?(_ e: TranscriptEntry) {
        switch e.kind {
        case .toolUse(_, let name, _) where ConnCue.kind(name) == nil:
            (kind, ok, ms) = (Self.kind(name), nil, nil)
        case .toolDone(_, let name, _, let ok, _, _, let ms) where ConnCue.kind(name) == nil:
            (kind, self.ok, self.ms) = (Self.kind(name), ok, ms)
        case .toolResult(_, let name, let ok, _, _, let ms) where ConnCue.kind(name ?? "") == nil:
            (kind, self.ok, self.ms) = (Self.kind(name ?? ""), ok, ms)
        case .toolEdit(_, _, _, _, _, let ok, let ms):
            (kind, self.ok, self.ms) = (.edit, ok, ms)
        default: return nil
        }
    }

    static func kind(_ name: String) -> Kind {
        if CodeModeTool.of(name) == .run { return .command }
        if CodeModeTool.of(name) == .search { return .search }
        return switch name.lowercased() {
        case "read", "notebookread": .read
        case "glob", "grep", "ls": .search
        case "edit", "write", "multiedit", "notebookedit": .edit
        case "bash", "shell": .command
        case "webfetch", "websearch": .web
        default: .other
        }
    }

    /// "Read 2 files · edited 2 files · ran 1 command".
    static func summary(_ steps: [ToolStep]) -> String {
        let parts: [String] = Kind.allCases.compactMap { k in
            let n = steps.filter { $0.kind == k }.count
            guard n > 0 else { return nil }
            return switch k {
            case .read: "read \(n) \(n == 1 ? "file" : "files")"
            case .search: "searched \(n) \(n == 1 ? "time" : "times")"
            case .edit: "edited \(n) \(n == 1 ? "file" : "files")"
            case .command: "ran \(n) \(n == 1 ? "command" : "commands")"
            case .web: "looked up \(n) \(n == 1 ? "page" : "pages")"
            case .other: "used \(n) \(n == 1 ? "tool" : "tools")"
            }
        }
        let s = parts.joined(separator: " · ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

/// One line of the transcript column, flat (a LazyVStack does not redraw a ForEach nested in its rows, 2026-11-15): an entry,
/// a run's header, or a step inside an open run. Headers take negative ids so they never meet an entry's seq.
struct ColumnRow: Identifiable {
    enum Kind {
        case entry(TranscriptEntry, inRun: Bool)
        case run([TranscriptEntry], open: Bool)
    }
    let kind: Kind
    var id: Int64 {
        switch kind {
        case .entry(let e, _): e.seq
        case .run(let es, _): -es[0].seq - 1
        }
    }

    /// The column's rows; `open` says whether a run (by its first seq) shows its steps.
    static func rows(_ items: [TranscriptItem], open: (Int64, [TranscriptEntry]) -> Bool) -> [ColumnRow] {
        var out: [ColumnRow] = []
        for item in items {
            switch item {
            case .one(let e): out.append(ColumnRow(kind: .entry(e, inRun: false)))
            case .run(let es):
                let o = open(es[0].seq, es)
                out.append(ColumnRow(kind: .run(es, open: o)))
                if o { out += es.map { ColumnRow(kind: .entry($0, inRun: true)) } }
            }
        }
        return out
    }

    /// A run starts open while it works or when a step failed.
    static func openByDefault(_ es: [TranscriptEntry]) -> Bool {
        es.compactMap(ToolStep.init).contains { $0.ok != true }
    }
}

/// A run of tool steps as one quiet row: what it did, how long, and its state. Its steps follow it in the column while it
/// is open; ⌥⌘→ / ⌥⌘← open or fold every run at once.
struct ToolRunHeader: View {
    let entries: [TranscriptEntry]
    let open: Bool
    let toggle: () -> Void
    @Environment(\.corePalette) private var palette

    private var steps: [ToolStep] { entries.compactMap(ToolStep.init) }
    private var running: Bool { steps.contains { $0.ok == nil } }
    private var failed: Int { steps.filter { $0.ok == false }.count }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Space.s2) {
                Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(palette.text2).rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: Space.s3)
                Text(ToolStep.summary(steps)).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Space.s2)
                trailing
            }
            .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
            .contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
        .help(open ? "Fold these steps (⌥⌘← folds them all)" : "Show each step (⌥⌘→ opens them all)")
        .accessibilityLabel(ToolStep.summary(steps))
        .accessibilityValue(open ? "Open" : "Folded")
        .keyHint(open ? .collapseSteps : .expandSteps)
    }

    @ViewBuilder private var trailing: some View {
        let secs = steps.compactMap(\.ms).reduce(0, +)
        HStack(spacing: Space.s2) {
            if running {
                CoreWorkingBar(width: Space.s8)
            } else {
                if secs > 0 {
                    Text("\(coreDecimal(Double(secs) / 1000, 1)) s").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(palette.text2).monospacedDigit()
                }
                if failed > 0 {
                    Label("\(failed) failed", systemImage: "xmark").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.tone(.fail).ink)
                } else {
                    Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.primary).accessibilityLabel("Done")
                }
            }
        }
    }
}

extension View {
    /// The conversation's reading column (Ahmed, 2026-11-15): prose stays a readable line long on a wide window, centred.
    func readingColumn() -> some View {
        frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
}
