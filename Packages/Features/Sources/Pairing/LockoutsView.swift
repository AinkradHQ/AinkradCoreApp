import CoreUI
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
            if app.service == nil {
                NotConnectedNote(what: "Lockouts")
            } else {
                LoadNote(state: model.load) { Task { await model.reload() } }
                if model.load == .ready && model.items.isEmpty {
                    Label("Nothing is locked right now.", systemImage: "checkmark").foregroundStyle(palette.text2)
                }
                ForEach(model.items) { l in
                    HStack(alignment: .top, spacing: Space.s3) {
                        Image(systemName: "lock").frame(width: MacSize.controlMd).foregroundStyle(palette.primary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(
                                LockoutsModel.describe(l.key).prefix(1).uppercased()
                                    + LockoutsModel.describe(l.key).dropFirst()
                            )
                            .font(.system(size: MacTextSize.headline, weight: .semibold))
                            Text(l.key).font(.system(size: MacTextSize.meta, design: .monospaced))
                                .foregroundStyle(palette.text2).textSelection(.enabled)
                            Text(
                                "Locked until \(l.lockedUntil.formatted(date: .omitted, time: .standard)). \(LockoutsModel.strikes(l.strikes))"
                            )
                            .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                        }
                        Spacer(minLength: Space.s2)
                        Button("Clear") { Task { await model.clear(l) } }
                            .buttonStyle(CoreButtonStyle(.secondary, busy: model.clearing == l.key))
                            .accessibilityLabel("Clear the lock on \(LockoutsModel.describe(l.key))")
                    }
                    .padding(Space.s3)
                    .background(palette.glassCard, in: coreShape(Radius.row))
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .frame(maxWidth: Space.s8 * 20, alignment: .leading)
        .task { await model.reload() }
    }
}
