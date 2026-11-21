import CoreUI
import SwiftUI

/// Brain: what it knows, what waits for you, and the one memory it asks about (keep or drop, in place).
struct BrainBody: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    let size: WidgetSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let b = shell.home.brain {
                content(b)
            } else {
                WHead("brain", "Brain")
                WEmpty(symbol: "brain", text: "Brain is not set up yet")
            }
        }
    }

    private func tone(_ b: HomeSnapshot.BrainGlance) -> Tone { b.health == "Healthy" ? .done : .warn }

    private func badge(_ b: HomeSnapshot.BrainGlance) -> StateBadge {
        StateBadge(b.health, tone: tone(b), symbol: b.health == "Healthy" ? "checkmark" : "exclamationmark.triangle")
    }

    /// "Tidying 3 rooms" while it works, "Learning quietly" while it does not.
    private func doing(_ b: HomeSnapshot.BrainGlance) -> (title: String, sub: String) {
        guard let p = b.pipeline else { return ("Learning quietly", "\(b.rooms) rooms") }
        switch p.now {
        case .distill: return ("Tidying \(p.working + p.queued) new notes", "Collect, then distill, then remember")
        case .remember: return ("Writing \(p.overviews) overviews", "Collect, then distill, then remember")
        default: return ("Learning quietly", "Nothing to tidy right now")
        }
    }

    /// Collect, Distill, Remember: done, at work, or still to come.
    private func flow(_ p: HomeSnapshot.BrainGlance.Pipeline, vertical: Bool) -> some View {
        let names = ["Collect", "Distill", "Remember"]
        let symbols = ["magnifyingglass", "sparkles", "externaldrive"]
        let layout =
            vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s2))
            : AnyLayout(HStackLayout(spacing: Space.s3))
        return layout {
            ForEach(0..<3, id: \.self) { i in
                let now = p.now?.rawValue == i
                let done = p.now.map { $0.rawValue > i } ?? true
                HStack(spacing: Space.s2) {
                    Image(systemName: done ? "checkmark" : symbols[i])
                        .foregroundStyle(now ? GlassInk.accent(paneAccent) : done ? GlassInk.green : GlassInk.secondary)
                        .frame(width: 18).accessibilityHidden(true)
                    Text(names[i]).coreFont(size: MacTextSize.body, weight: now ? .semibold : .regular)
                        .foregroundStyle(now ? GlassInk.primary : GlassInk.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(now ? "Working" : done ? "Done" : "Waiting")
            }
        }
    }

    @ViewBuilder private func content(_ b: HomeSnapshot.BrainGlance) -> some View {
        let d = doing(b)
        switch size {
        case .s:
            WHead("brain", "Brain")
            WFigure(value: Double(b.known), format: { Int($0).formatted() }, caption: "things known")
            Spacer(minLength: 0)
            WCaption(b.waiting > 0 ? "\(b.waiting) waiting for you" : "Learning quietly")
        case .m:
            WHead("brain", "Brain") { badge(b) }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.title).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.primary)
                WCaption(d.sub)
            }
            if let x = b.pipeline?.progress { CoreMeter(x, label: "Tidying progress") }
            Spacer(minLength: 0)
        case .w:
            WHead("brain", "Brain") { badge(b) }
            HStack(alignment: .center, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    if let p = b.pipeline { flow(p, vertical: false) }
                    WCaption(d.title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let q = b.question { question(q).frame(maxWidth: .infinity) }
            }
        case .l:
            WHead("brain", "Brain") { badge(b) }
            if let p = b.pipeline { flow(p, vertical: true) }
            if let x = b.pipeline?.progress { CoreMeter(x, label: "Tidying progress") }
            WCaption(d.title)
            HStack(alignment: .top, spacing: Space.s5) {
                stat("Rooms", "\(b.rooms)")
                stat("Known", b.known.formatted())
                stat(
                    "Last",
                    b.pipeline?.lastDoneAt.map {
                        $0.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
                    } ?? "None")
                Spacer(minLength: 0)
            }
            if let q = b.question { question(q) }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WCaption(k)
            Text(v).coreFont(size: 20, weight: .bold).foregroundStyle(GlassInk.primary).lineLimit(1)
                .minimumScaleFactor(0.6).contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private func question(_ q: HomeSnapshot.BrainGlance.Question) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Is this still right?").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            Text(q.text).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.primary)
                .lineLimit(size == .l ? 4 : 2)
            HStack(spacing: Space.s2) {
                Button("Not anymore") { shell.answerBrainQuestion?(q.id, q.room, false) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Yes") { shell.answerBrainQuestion?(q.id, q.room, true) }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.row))
    }
}

/// Today note: the title, a line of text and the checklist. A tick writes back to the note.
struct TodayNoteBody: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    let size: WidgetSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let n = shell.home.note {
                content(n)
            } else {
                WHead("note.text", "Today note")
                WEmpty(symbol: "note.text", text: "Nothing written today")
            }
        }
    }

    private var count: (HomeSnapshot.NoteFact) -> String {
        { $0.todos.isEmpty ? "" : "\($0.doneCount) of \($0.todos.count) done" }
    }

    @ViewBuilder private func content(_ n: HomeSnapshot.NoteFact) -> some View {
        switch size {
        case .s:
            WHead("note.text", "Today note")
            Spacer(minLength: 0)
            Text(n.title).coreFont(size: MacTextSize.title, weight: .semibold).foregroundStyle(GlassInk.primary)
                .lineLimit(2)
            WCaption(count(n))
        case .m:
            WHead("note.text", "Today note")
            todos(n, limit: 3)
        case .w:
            WHead("note.text", "Today note") { WCaption(count(n)) }
            HStack(alignment: .top, spacing: Space.s4) {
                paragraph(n).frame(maxWidth: .infinity, alignment: .topLeading)
                todos(n, limit: 3).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .l:
            WHead("note.text", "Today note") { WCaption(count(n)) }
            paragraph(n)
            todos(n, limit: 6)
            Spacer(minLength: 0)
        }
    }

    private func paragraph(_ n: HomeSnapshot.NoteFact) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(n.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
            if !n.paragraph.isEmpty, n.paragraph != n.title {
                Text(n.paragraph).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(3)
            }
        }
        .foregroundStyle(GlassInk.primary)
    }

    private func todos(_ n: HomeSnapshot.NoteFact, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(n.todos.prefix(limit).enumerated()), id: \.offset) { i, t in
                Button {
                    shell.toggleNoteTodo?(i)
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: t.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(t.done ? GlassInk.accent(paneAccent) : GlassInk.secondary)
                            .accessibilityHidden(true)
                        Text(t.text).coreFont(size: MacTextSize.body).lineLimit(1)
                            .strikethrough(t.done).foregroundStyle(t.done ? GlassInk.secondary : GlassInk.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.text)
                .accessibilityValue(t.done ? "Done" : "Not done")
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}
