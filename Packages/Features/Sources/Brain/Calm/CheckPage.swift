import CoreUI
import SwiftUI

/// To check: one question at a time. Why Brain asks and where, the thing itself, what it knows around it, then Not Right
/// (⌫), Later, or Keep (⏎). A duplicate asks Keep Both or Make One. The next card waits underneath; answering slides the
/// top one away (with Reduce Motion it fades).
struct CheckPage: View {
    let brain: BrainModel
    @State private var leaving: String?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        let queue = brain.checkQueue
        let done = brain.calm.checked
        let all = queue.count + done
        VStack(alignment: .leading, spacing: Space.s4) {
            BrainHead(
                symbol: "tray", title: "To check", sub: "Brain asks only when it is not sure. One answer at a time.")
            if let c = queue.first {
                VStack(spacing: Space.s4) {
                    HStack(spacing: Space.s3) {
                        Text("\(min(done + 1, all)) of \(all)").monospacedDigit().contentTransition(.numericText())
                        CoreMeter(all > 0 ? Double(done) / Double(all) : 0, label: "Checked \(done) of \(all)")
                        Text("about \(queue.count * 10) seconds left").monospacedDigit()
                    }
                    .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    VStack(spacing: 0) {
                        card(c)
                            .id(c.id)
                            .transition(
                                reduce
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                        removal: .opacity.combined(with: .offset(x: leaving == "keep" ? 60 : -60))))
                        // The next question waits underneath, its edge showing.
                        if queue.count > 1 {
                            UnevenRoundedRectangle(
                                bottomLeadingRadius: Radius.pane, bottomTrailingRadius: Radius.pane, style: .continuous
                            )
                            .fill(GlassInk.well).frame(height: Space.s2).padding(.horizontal, Space.s5)
                            .accessibilityHidden(true)
                        }
                    }
                }
                .frame(maxWidth: Space.s8 * 20)
                .frame(maxWidth: .infinity)
                .animation(Motion.calm(Motion.out(Motion.move), reduce), value: c.id)
            } else {
                allChecked
            }
            Spacer(minLength: 0)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.return) {
            guard let c = queue.first else { return .ignored }
            answer(c, .keep)
            return .handled
        }
        .onKeyPress(.delete) {
            guard let c = queue.first else { return .ignored }
            answer(c, .drop)
            return .handled
        }
        .onAppear { brain.calm.resetChecks() }
        .accessibilityIdentifier("brain-check")
    }

    private func card(_ c: InboxCandidate) -> some View {
        let dup = c.reason == "duplicate"
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "info.circle").accessibilityHidden(true)
                if let why = CheckWords.why(c.reason) { Text("\(why) ·") }
                PlaceChip(name: c.roomName)
            }
            .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
            Text(CheckWords.question(c)).coreFont(size: MacTextSize.body, weight: .semibold)
                .foregroundStyle(GlassInk.secondary)
            Text(c.text).font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let ctx = CheckWords.context(c) {
                Text(ctx).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GlassInk.well, in: coreShape(Radius.control))
            }
            HStack(spacing: Space.s2) {
                Button {
                    answer(c, .drop)
                } label: {
                    Label(dup ? "Keep Both" : "Not Right", systemImage: "xmark")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).environment(\.coreKeycap, "⌫")
                .help(dup ? "Keep both as they are (⌫)" : "Brain will not use it (⌫)")
                Button("Later") { answer(c, .later) }.buttonStyle(CoreButtonStyle(.plain))
                    .help("Ask again after the others")
                Spacer(minLength: Space.s2)
                Button {
                    answer(c, .keep)
                } label: {
                    Label(dup ? "Make One" : "Keep", systemImage: "checkmark")
                }
                .buttonStyle(CoreButtonStyle(.prominent)).environment(\.coreKeycap, "⏎")
                .help(dup ? "Keep only the one Brain already has (⏎)" : "Yes, keep it (⏎)")
                .accessibilityIdentifier("brain-check-keep")
            }
            .disabled(brain.candidates.busy)
            .padding(.top, Space.s6)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell(radius: Radius.pane)
        .accessibilityElement(children: .contain)
    }

    private var allChecked: some View {
        VStack(spacing: Space.s3) {
            BrainTile(symbol: "checkmark", size: Space.s8 + Space.s6, tint: palette.success)
            Text("All checked").coreFont(size: MacTextSize.title, weight: .semibold)
            Text("Nothing waits for you. Brain asks again only when it is unsure.")
                .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s8).frame(maxWidth: .infinity).coreWell()
        .transition(.opacity)
        .accessibilityIdentifier("brain-check-done")
    }

    private func answer(_ c: InboxCandidate, _ a: BrainModel.CheckAnswer) {
        leaving = a == .drop ? "drop" : "keep"
        Task { await brain.answer(c, a) }
    }
}
