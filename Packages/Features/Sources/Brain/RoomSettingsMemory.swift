import CoreUI
import SwiftUI

/// Place Settings, memory half (B10-02): what the room saves by itself, its daily distil cap, how long it keeps sources, and
/// the "Clean up memory…" run. Plain and quick by default: every kind is saved with Undo, nothing to review. Every change
/// asks for Touch ID (the model asks); until the Core answers, the controls show what the Core has.
extension RoomSettings {
    // MARK: what Brain keeps

    /// Each kind as a tile with its box; then how often a thing must be seen before it is kept.
    func saving(_ p: RoomPolicy) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 4), spacing: Space.s2)
            {
                ForEach(CandidateKind.saveRows, id: \.self) { k in
                    KeepTile(
                        symbol: Self.keepSymbol(k), title: k.plural, sub: Self.saveAbout(k),
                        on: Binding(get: { p.saves(k) }, set: { _ in Task { await c.toggleSave(room.id, k) } }))
                }
            }
            line("Keep something only when it was seen", "More times means fewer, surer things") {
                CoreSelect(
                    nil,
                    selection: Binding(get: { p.minSources }, set: { n in Task { await c.setMinSources(room.id, n) } }),
                    options: Self.minChoices(p.minSources).map { CoreSelectOption($0, Self.seen($0)) }
                )
                .frame(width: Space.s8 * 5)
                .disabled(p.savedTypes.isEmpty)
            }
        }
    }

    static func seen(_ n: Int) -> String {
        switch n {
        case 1: "at least once"
        case 2: "at least twice"
        default: "\(n) times or more"
        }
    }

    static func keepSymbol(_ k: CandidateKind) -> String {
        switch k {
        case .fact: "sparkles"
        case .decision: "star"
        case .preference: "person"
        case .rule: "checkmark"
        case .task: "tray"
        case .projectState: "square.grid.2x2"
        default: "doc"
        }
    }

    static func saveAbout(_ k: CandidateKind) -> String {
        switch k {
        case .fact: "Plain statements"
        case .decision: "Something was chosen"
        case .preference: "How you like things done"
        case .rule: "Always or never do this"
        case .task: "Something to do"
        case .projectState: "Where a project stands"
        case .summary: "A short recap"
        default: k.about
        }
    }

    static func capChoices(_ current: Int) -> [Int] { Set([0, 6, 12, 25, 50, 100, current]).sorted() }

    // MARK: Retention

    func retention(_ p: RoomPolicy) -> some View {
        let care = model.care
        let ask = care?.roomID == room.id ? care?.retentionAsk : nil
        return VStack(alignment: .leading, spacing: Space.s2) {
            line("Keep the original text") {
                CoreSelect(
                    nil,
                    selection: Binding(
                        get: { ask?.days ?? p.retentionDays ?? 0 }, set: { n in pick(n, p) }),
                    options: Self.retentionChoices(p.retentionDays).map {
                        CoreSelectOption($0, $0 == 0 ? "Forever" : "\($0) days")
                    }
                )
                .frame(width: Space.s8 * 5)
            }
            if let ask { retentionAsk(ask) }
        }
    }

    static func retentionChoices(_ current: Int?) -> [Int] { Set([0, 30, 90, 180, 365, current ?? 0]).sorted() }

    private func pick(_ n: Int, _ p: RoomPolicy) {
        if n == (p.retentionDays ?? 0) {
            model.care.cancelRetention()
        } else if n == 0 {
            Task { await model.care.keepEverything(room.id) }
        } else {
            model.care.askRetention(room.id, days: n)
        }
    }

    /// The count comes first; turning it on is a second, deliberate step because compaction cannot be undone.
    @ViewBuilder private func retentionAsk(_ ask: RoomCareModel.RetentionAsk) -> some View {
        if let why = ask.failed {
            CoreNotice(
                symbol: "exclamationmark.triangle", title: "Unable to count what it would remove", text: why,
                tone: .fail
            ) {
                HStack(spacing: Space.s2) {
                    Button("Try Again") { model.care.askRetention(room.id, days: ask.days) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    Button("Cancel") { model.care.cancelRetention() }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        } else if let p = ask.preview {
            CoreNotice(
                symbol: "clock.arrow.circlepath",
                title: p.wouldCompact == 0
                    ? "Nothing is \(ask.days) days old yet"
                    : "\(BrainWords.plural(p.wouldCompact, "source", "sources")) would lose their text",
                text: p.wouldCompact == 0
                    ? "Sources that reach \(ask.days) days and are distilled are compacted from then on."
                    : "About \(p.chars.formatted()) characters. Each keeps its title and a citation. This cannot be undone.",
                tone: .warn
            ) {
                HStack(spacing: Space.s2) {
                    Button {
                        Task { await model.care.confirmRetention(room.id) }
                    } label: {
                        Label("Turn On", systemImage: "touchid")
                    }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    Button("Cancel") { model.care.cancelRetention() }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        } else {
            HStack(spacing: Space.s2) {
                CoreWorkingBar(width: Space.s8 * 3)
                Text("Counting what it would remove…").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            .frame(minHeight: MacSize.controlSm, alignment: .leading)
        }
    }
}

/// "Clean up memory…": the dry run starts at once and says what would change in one line; Apply (Touch ID) shows progress
/// with Cancel; the result line has Undo and a way to the Activity tab, where the change set is listed.
struct RoomCleanupCard: View {
    let model: BrainModel
    let room: RoomSummary
    private var care: RoomCareModel { model.care }
    private var state: RoomCareModel.Cleanup { care.roomID == room.id ? care.cleanup : .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            content
            if let note = care.roomID == room.id ? care.note : nil {
                CoreNotice(symbol: "exclamationmark.triangle", title: note, tone: .warn)
            }
        }
        .task(id: room.id) { await care.enter(room.id) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-cleanup")
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle:
            Button {
                care.check(room.id)
            } label: {
                Label("Clean Up Memory…", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .help("Count what a clean-up would keep and put away. Nothing changes yet.")
        case .checking(let run):
            progress("Checking what would change…", run)
        case .ready(let run):
            ready(run)
        case .applying(let run):
            progress("Cleaning up…", run)
        case .done(let run):
            done(run)
        case .nothing:
            CoreNotice(
                symbol: "tray", title: "Nothing to clean up",
                text: "This place has nothing to read again yet."
            ) {
                Button("Dismiss") { care.dismiss() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        case .failed(let why):
            CoreNotice(symbol: "exclamationmark.triangle", title: "Clean up did not finish", text: why, tone: .fail) {
                HStack(spacing: Space.s2) {
                    Button("Try Again") { care.check(room.id) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    Button("Dismiss") { care.dismiss() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        }
    }

    /// A bar that fills while the Core reads, the count under it, and Cancel (safe until the result is being written).
    private func progress(_ title: String, _ run: RedistilRun?) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                if let run, run.total > 0 {
                    CoreMeter(run.fraction, height: Space.s1 + 2, label: title).frame(width: Space.s8 * 6)
                    Text("\(run.read.formatted()) of \(BrainWords.plural(run.total, "source", "sources"))")
                        .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).monospacedDigit()
                } else {
                    CoreWorkingBar(width: Space.s8 * 6)
                }
            }
            Spacer(minLength: Space.s3)
            Button("Cancel") { care.cancel(room.id) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .help("Stop. Nothing is archived.")
        }
    }

    /// The dry run's one line, and the choice it leads to.
    private func ready(_ run: RedistilRun) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(run.plan).coreFont(size: MacTextSize.body, weight: .medium)
                Text("Nothing has changed yet. Apply can be undone.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s3)
            Button("Cancel") { care.dismiss() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            Button {
                care.apply(room.id)
            } label: {
                Label("Apply", systemImage: "touchid")
            }
            .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            .help("Clean up this room's memory. Asks for Touch ID.")
        }
    }

    private func done(_ run: RedistilRun) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(run.summary ?? run.plan).coreFont(size: MacTextSize.body, weight: .medium)
                if let id = run.change, let why = model.changes.undoFailed[id] {
                    Text(why).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.redInk)
                }
            }
            Spacer(minLength: Space.s3)
            if let id = run.change {
                if let u = care.undone(id) {
                    Text(ChangesModel.sentence(u)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                } else {
                    Button("Undo") { care.undo(id) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .disabled(model.changes.undoing.contains(id))
                        .help("Put back everything this clean-up archived.")
                }
                Button("See Changes") { care.openActivity() }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Open Activity to see what it kept and archived.")
            }
            Button("Dismiss") { care.dismiss() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
        }
    }
}

/// One kind Brain may keep: its tile, name, what it means and its box. Off reads dimmer.
private struct KeepTile: View {
    let symbol: String
    let title: String
    let sub: String
    @Binding var on: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1 + 2) {
            HStack {
                BrainTile(symbol: symbol, size: Space.s5 + 4)
                Spacer(minLength: Space.s2)
                CoreCheckbox("", isOn: $on, spoken: title)
            }
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
            Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.control + 2))
        .opacity(on ? 1 : 0.55)
        .contentShape(coreShape(Radius.control + 2))
        .onTapGesture { on.toggle() }
        .accessibilityElement(children: .contain)
    }
}
