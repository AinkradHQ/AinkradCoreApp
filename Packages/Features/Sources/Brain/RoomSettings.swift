import CoreUI
import SwiftUI

/// A place's Settings as plain questions (Designs/core/0-10/review/brain/place.html): who reads and writes, what Brain
/// keeps, how often it learns, how long it keeps what it read, which AI sessions may use it, and starting fresh. The
/// controls and their Touch ID steps are the ones the place always had; until the Core answers, they show what it has.
struct RoomSettings: View {
    let model: BrainModel
    let room: RoomSummary
    var c: BrainCandidates { model.candidates }
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            if let p = c.policy(room.id) {
                if p.needsLocalModel { queue(p) }
                PlaceQuestion(
                    symbol: "cloud", lit: true, title: "Who reads and writes this place’s knowledge?",
                    sub: "Brain turns what it reads into knowledge with an AI. Pick where that happens.",
                    lock: "Touch ID to change"
                ) { who(p) }
                .coreRise(shown, 0)
                PlaceQuestion(
                    symbol: "cylinder", title: "What should Brain keep from here?",
                    sub: "Turn off what you don’t want remembered. You can undo anything it keeps from Activity."
                ) { saving(p) }
                .coreRise(shown, 1)
                pair(
                    p.dailyDistils.map { cap in
                        PlaceQuestion(
                            symbol: "clock", title: "How often may it learn?",
                            sub: "Each time it reads what is new here. More often uses more of your AI plan."
                        ) { often(cap) }
                    },
                    model.service?.servesCare == true
                        ? PlaceQuestion(
                            symbol: "clock.arrow.circlepath", title: "How long to keep what it read?",
                            sub:
                                "After that the text goes; what Brain learned from it stays, with a note of where it came from.",
                            lock: "Touch ID"
                        ) { retention(p) } : nil
                )
                .coreRise(shown, 2)
                pair(
                    c.access[room.id] != nil
                        ? PlaceQuestion(
                            symbol: "sparkles", title: "Which AI sessions can use it?",
                            sub: "A session sees this place only when it works on a matching project.", lock: "Touch ID"
                        ) { RoomAISessions(c: c, room: room) } : nil,
                    model.service?.servesCare == true
                        ? PlaceQuestion(
                            symbol: "arrow.clockwise", title: "Start this place’s memory fresh?",
                            sub: "Brain reads everything here again, keeps what still holds and puts the rest away. "
                                + "Undo brings it all back."
                        ) { RoomCleanupCard(model: model, room: room) } : nil
                )
                .coreRise(shown, 3)
                instructions
            } else {
                BrainSkeleton(shape: .list)
            }
        }
        .onAppear { shown = true }
        .task(id: room.id) {
            await c.loadPolicy(room.id)
            await c.loadAccess(room.id)
            if model.servesOverview, model.roomOverview.roomID != room.id { await model.roomOverview.open(room.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room-settings")
    }

    /// Two questions side by side, or the one there is across the width.
    @ViewBuilder private func pair<A: View, B: View>(_ a: A?, _ b: B?) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            if let a { a }
            if let b { b }
        }
    }

    func hint(_ s: String) -> some View {
        Text(s).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: queue

    private func queue(_ p: RoomPolicy) -> some View {
        CoreNotice(
            symbol: "icloud.slash", title: "Needs a local model",
            text:
                "\(BrainWords.plural(p.queued, "item is", "items are")) queued. This place learns only on your own "
                + "machines and no runner has a local model yet. They are read as soon as one is ready.",
            tone: .warn
        ) {
            Button("Use Your AI Accounts") { Task { await c.setModel(room.id, .cloud) } }
                .buttonStyle(CoreButtonStyle(.prominent, size: .small))
        }
        .accessibilityIdentifier("room-queued")
    }

    // MARK: who reads and writes

    @ViewBuilder private func who(_ p: RoomPolicy) -> some View {
        HStack(spacing: Space.s2) {
            PlaceChoice(
                symbol: "cloud", title: "Your AI accounts",
                text: "Best results. Text from this place goes to the account that is first in your AI order.",
                on: p.model == .cloud
            ) { Task { await c.setModel(room.id, .cloud) } }
            PlaceChoice(
                symbol: "laptopcomputer", title: "Only on your own machines",
                text: "Nothing leaves your machines. Slower, and it learns less.", on: p.model == .localOnly
            ) { Task { await c.setModel(room.id, .localOnly) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model policy")
        HStack(spacing: Space.s2) {
            if p.model == .cloud {
                Text(p.accounts.isEmpty ? "No AI account set up yet." : "Uses your AI order:")
                ForEach(Array(p.accounts.enumerated()), id: \.offset) { i, a in
                    if i > 0 {
                        Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta)
                            .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    }
                    PlaceTag(symbol: "sparkles", text: a)
                }
                Button("Change AI Order…", action: openAccounts).buttonStyle(.plain).brainAccentInk()
                    .help("Open Accounts to change which AI account comes first (\(p.provider))")
            } else if p.localModels.isEmpty {
                Text("No local model yet. A runner with one appears here; no AI account is ever used.")
            } else {
                Text("Uses your local model:")
                ForEach(p.localModels, id: \.self) { PlaceTag(symbol: "cpu", text: $0) }
            }
        }
        .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
    }

    private func openAccounts() {
        model.host.shell.settings.selected = "accounts-link"
        model.host.shell.open(.settings)
    }

    // MARK: how often

    private func often(_ cap: Int) -> some View {
        line("Learn at most") {
            CoreSelect(
                nil, selection: Binding(get: { cap }, set: { n in Task { await c.setDailyDistils(room.id, n) } }),
                options: Self.capChoices(cap).map {
                    CoreSelectOption($0, $0 == 0 ? "Never by itself" : "\($0) times a day")
                }
            )
            .frame(width: Space.s8 * 5)
        }
    }

    /// A label on the left and its control on the right.
    func line<T: View>(_ title: String, _ sub: String? = nil, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.body)
                if let sub { Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary) }
            }
            Spacer(minLength: Space.s3)
            trailing()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: what AI sessions are told

    /// The instructions AI sessions read here, once an overview is written (they came with the old Overview tab).
    @ViewBuilder private var instructions: some View {
        let o: RoomOverviewModel = model.roomOverview
        if o.roomID == room.id, let cur = o.current, let body = cur.overview {
            InstructionsCard(
                o: o, room: room.id, overview: body, approved: cur.instructionsApproved, text: cur.instructionsText)
        }
    }

    static func minChoices(_ current: Int) -> [Int] { Set([1, 2, 3, 5, 10, current]).sorted() }
}

/// One question card: its tile, the question and a line under it, the Touch ID note, then its controls.
struct PlaceQuestion<Content: View>: View {
    let symbol: String
    var lit = false
    let title: String
    let sub: String
    var lock: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                BrainTile(symbol: symbol, lit: lit, size: Space.s6 + Space.s1 + 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .semibold).accessibilityAddTraits(.isHeader)
                    Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s3)
                if let lock {
                    Label(lock, systemImage: "lock").coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).fixedSize()
                }
            }
            content
        }
        .padding(.horizontal, Space.s4 + 2).padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
        .accessibilityElement(children: .contain)
    }
}

/// One of two answers, as a tile: the chosen one lit.
private struct PlaceChoice: View {
    let symbol: String
    let title: String
    let text: String
    let on: Bool
    let pick: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: pick) {
            HStack(alignment: .top, spacing: Space.s3) {
                BrainTile(symbol: symbol, lit: on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(text).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlaceSelectFill(on: on, hover: hover))
            .contentShape(coreShape(Radius.control + 2))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(on ? "\(title): chosen" : "Use \(title.lowercased()). Asks for Touch ID.")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A small name in a quiet rounded rect: an AI account, a local model.
struct PlaceTag: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol).lineLimit(1)
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2).padding(.vertical, 3)
            .background(GlassInk.well, in: coreShape(Radius.chip))
    }
}

/// The fill of a tile you pick from: a well, lifted with the accent when chosen and a little on hover.
struct PlaceSelectFill: View {
    let on: Bool
    let hover: Bool
    @Environment(\.coreAccent) private var accent

    var body: some View {
        coreShape(Radius.control + 2).fill(GlassInk.well)
            .overlay(coreShape(Radius.control + 2).fill(GlassInk.accent(accent).opacity(on ? 0.22 : 0)))
            .overlay(coreShape(Radius.control + 2).fill(GlassInk.primary.opacity(on ? 0.07 : hover ? 0.04 : 0)))
    }
}
