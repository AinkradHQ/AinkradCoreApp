import CoreUI
import Shell
import SwiftUI

struct LockoutsSection: View {
    let app: AppModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = app.lockouts!
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(
                "The Core locks an address or a device for a while after repeated failed attempts. Clearing a lock needs Touch ID."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            StepUpBanner(app: app)
            if app.service == nil {
                NotConnectedNote(what: "Lockouts")
            } else {
                LoadNote(state: model.load) { Task { await model.reload() } }
                if model.load == .ready && model.items.isEmpty {
                    Label("Nothing is locked right now.", systemImage: "checkmark").foregroundStyle(palette.text2)
                }
                ForEach(model.items) { l in LockRow(model: model, lock: l) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.reload() }
    }
}

/// One lock: who, a live countdown with a bar that shrinks (amber in the last minute), and Clear. At zero the lock has ended.
private struct LockRow: View {
    let model: LockoutsModel
    let lock: LockoutInfo
    @Environment(\.corePalette) private var palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(lock.lockedUntil.timeIntervalSince(ctx.date).rounded(.up)))
            let soon = left > 0 && left <= 60
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "lock").frame(width: MacSize.controlMd).foregroundStyle(palette.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(
                        LockoutsModel.describe(lock.key).prefix(1).uppercased()
                            + LockoutsModel.describe(lock.key).dropFirst()
                    )
                    .font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(lock.key).font(.system(size: MacTextSize.meta, design: .monospaced))
                        .foregroundStyle(palette.text2).textSelection(.enabled)
                    HStack(spacing: Space.s2) {
                        Text(left == 0 ? "Ended" : soon ? "Ends in \(Countdown.text(left))" : "\(Countdown.text(left)) left")
                            .font(.system(size: MacTextSize.meta, weight: .medium).monospacedDigit())
                            .foregroundStyle(soon ? palette.tone(.warn).ink : palette.text)
                        CoreMeter(
                            Double(left) / LockMeter.total(left), low: soon, label: "Lock time left"
                        )
                        .frame(maxWidth: Space.s8 * 4)
                    }
                    Text(
                        "Locked until \(lock.lockedUntil.formatted(date: .omitted, time: .standard)). \(LockoutsModel.strikes(lock.strikes))"
                    )
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
                Spacer(minLength: Space.s2)
                Button(left == 0 ? "Ended" : "Clear") { Task { await model.clear(lock) } }
                    .buttonStyle(CoreButtonStyle(.secondary, busy: model.clearing == lock.key))
                    .disabled(left == 0)
                    .accessibilityLabel(
                        left == 0
                            ? "The lock on \(LockoutsModel.describe(lock.key)) has ended"
                            : "Clear the lock on \(LockoutsModel.describe(lock.key))")
            }
            .padding(Space.s3)
            .background(palette.glassCard, in: coreShape(Radius.row))
            .accessibilityElement(children: .contain)
        }
    }
}

/// The Core doubles each lock (1, 2, 4 ... 60 minutes): the bar measures what is left against the next length up from it.
enum LockMeter {
    static func total(_ left: Int) -> Double {
        var minutes = 1
        while minutes * 60 < left, minutes < 60 { minutes *= 2 }
        return Double(max(min(minutes, 60) * 60, left, 1))
    }
}
