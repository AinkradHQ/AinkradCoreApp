import CoreUI
import SwiftUI

/// A memory waiting for you. Keys on the focused card: ⌘↩ approve, ⌘⌫ reject, E edit, up and down move.
struct CandidateCard: View {
    let model: BrainModel
    let c: Candidate
    let approve: () -> Void
    let reject: () -> Void
    let edit: () -> Void
    let advanced: () -> Void

    var body: some View {
        let busy = model.busy != nil
        InboxCardFrame(edge: c.flag == nil ? nil : GlassInk.red) {
            CardHeader(chip: c.type.label, hue: GlassInk.blue, title: c.title, age: c.age)
            QuotedText(text: c.text)
            HStack(spacing: Space.s2) {
                SourceBadge(source: c.source)
                Text("Proposed by \(c.by)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if let flag = c.flag { InboxNote("exclamationmark.triangle", GlassInk.red, flag) }
            if let why = model.inboxState.errors[c.id] {
                InboxNote("exclamationmark.triangle", GlassInk.red, why)
                Button("Try again", action: approve).buttonStyle(CoreButtonStyle(.plain, size: .small))
            }
            HStack(spacing: Space.s2) {
                Button(action: reject) { KeyLabel("Reject", key: "⌘⌫") }
                    .buttonStyle(CoreButtonStyle(.secondary)).help(
                        "Reject this memory. The proposer is told it was not used.")
                Button(action: edit) { KeyLabel("Edit", key: "E") }
                    .buttonStyle(CoreButtonStyle(.secondary)).help("Change the title or text, then approve.")
                Spacer(minLength: Space.s2)
                Button("Approve with options…", action: advanced).buttonStyle(CoreButtonStyle(.plain))
                    .help("Choose who it applies to, who said so and when it ends.")
                Button(action: approve) { KeyLabel("Approve", key: "⌘↩") }
                    .buttonStyle(CoreButtonStyle(.prominent)).help(
                        "Approve with the room defaults. AI sessions can use it at once.")
            }
            .disabled(busy)
        }
        .help("Memory id: \(c.id)")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory waiting: \(c.title). Command Return approves, Command Delete rejects.")
        .accessibilityIdentifier("inbox-card-\(c.id)")
    }
}

/// Two memories in one room that disagree, side by side.
struct ConflictCard: View {
    let model: BrainModel
    let c: Conflict
    let keep: (ConflictChoice) -> Void

    var body: some View {
        let busy = model.busy != nil
        InboxCardFrame {
            CardHeader(chip: "Conflict", hue: GlassInk.blue, title: c.title, age: c.age)
            if model.inboxState.later.contains(c.id) {
                InboxNote("bell", GlassInk.slate, "Asked again later. It stays here and in the bell.")
            }
            HStack(alignment: .top, spacing: Space.s3) {
                side(c.a, "First", .first)
                side(c.b, "Second", .second)
            }
            if let why = model.inboxState.errors[c.id] { InboxNote("exclamationmark.triangle", GlassInk.red, why) }
            HStack(spacing: Space.s2) {
                Button("Ask me later") { model.askLater(c.id) }.buttonStyle(CoreButtonStyle(.plain))
                Spacer(minLength: Space.s2)
                Button("Keep first") { keep(.first) }.buttonStyle(CoreButtonStyle(.secondary))
                Button("Keep second") { keep(.second) }.buttonStyle(CoreButtonStyle(.secondary))
                Button("Keep both") { keep(.both) }.buttonStyle(CoreButtonStyle(.prominent))
                    .disabled(c.sameScope).help(
                        c.sameScope
                            ? "Both say the same scope, so they cannot both stay."
                            : "Keep both, scoped: each one applies only to its own scope.")
            }
            .disabled(busy)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-conflict-\(c.id)")
    }

    private func side(_ s: ConflictSide, _ title: String, _ choice: ConflictChoice) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).foregroundStyle(GlassInk.secondary)
            QuotedText(text: s.text)
            ChipFlow(spacing: Space.s2) {
                SourceBadge(source: s.source)
                BrainChip(s.authority.label, GlassInk.slate, help: "Authority id: \(s.authority.rawValue)")
                BrainChip("Applies to: \(s.scope)", GlassInk.slate)
            }
            Text(s.when).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            if let higher = model.overridden(c, choice) {
                Text("Keeping this one replaces a higher source (\(higher.label)). Touch ID asks.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.amberInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A note a room rule stopped. It names the rule and never shows the secret.
struct BlockedCard: View {
    let model: BrainModel
    let b: BlockedNote
    let redact: () -> Void
    let discard: () -> Void

    var body: some View {
        InboxCardFrame {
            CardHeader(chip: "Blocked", hue: GlassInk.red, title: b.title, age: b.age)
            InboxNote("shield", GlassInk.red, "Blocked by \(b.ruleName)", b.ruleAbout)
            HStack(spacing: Space.s2) {
                SourceBadge(source: b.source)
                Text("Captured by \(b.by)").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if let why = model.inboxState.errors[b.id] { InboxNote("exclamationmark.triangle", GlassInk.red, why) }
            HStack(spacing: Space.s2) {
                Button("Discard…", action: discard).buttonStyle(CoreButtonStyle(.secondary))
                    .help("Wipe the note from this Mac. Touch ID asks.")
                Spacer(minLength: Space.s2)
                Button("Redact and keep", action: redact).buttonStyle(CoreButtonStyle(.prominent))
                    .help("Remove the secret and keep the rest. The cleaned note waits in Waiting.")
            }
            .disabled(model.busy != nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-blocked-\(b.id)")
    }
}
