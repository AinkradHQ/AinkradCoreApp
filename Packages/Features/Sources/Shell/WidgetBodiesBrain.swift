import CoreUI
import SwiftUI

/// Brain: what it knows, what waits for you, and the one memory it asks about (keep or drop, in place).
struct BrainBody: View {
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

    @ViewBuilder private func content(_ b: HomeSnapshot.BrainGlance) -> some View {
        switch size {
        case .s:
            WHead("brain", "Brain")
            WFigure(value: Double(b.known), format: { Int($0).formatted() }, caption: "things known")
            Spacer(minLength: 0)
            WCaption(b.waiting > 0 ? "\(b.waiting) waiting for you" : "Learning quietly")
        case .m:
            WHead("brain", "Brain") { badge(b) }
            if let q = b.question {
                question(q)
            } else {
                HStack(alignment: .top, spacing: Space.s5) {
                    stat("Known", b.known.formatted())
                    stat("Rooms", "\(b.rooms)")
                    stat("Waiting", "\(b.waiting)")
                    Spacer(minLength: 0)
                }
            }
        case .w:
            WHead("brain", "Brain") { badge(b) }
            HStack(alignment: .top, spacing: Space.s4) {
                HStack(alignment: .top, spacing: Space.s5) {
                    stat("Known", b.known.formatted())
                    stat("Rooms", "\(b.rooms)")
                    stat("Waiting", "\(b.waiting)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let q = b.question { question(q).frame(maxWidth: .infinity) }
            }
        case .l:
            WHead("brain", "Brain") { badge(b) }
            HStack(alignment: .top, spacing: Space.s5) {
                stat("Known", b.known.formatted())
                stat("Rooms", "\(b.rooms)")
                stat("Waiting", "\(b.waiting)")
                Spacer(minLength: 0)
            }
            if let q = b.question { question(q) } else { WCaption("Nothing to ask you right now") }
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
            Text("Keep this in memory?").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            Text(q.text).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.primary)
                .lineLimit(size == .l ? 4 : 2)
            HStack(spacing: Space.s2) {
                Button("Drop") { shell.answerBrainQuestion?(q.id, q.room, false) }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                Button("Keep") { shell.answerBrainQuestion?(q.id, q.room, true) }
                    .buttonStyle(CoreButtonStyle(.prominent, size: .small))
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.row))
    }
}

/// Today note: the title, a line of text and the checklist. A tick writes back to the note.
struct TodayNoteBody: View {
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
                            .foregroundStyle(t.done ? GlassInk.blue : GlassInk.secondary)
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
