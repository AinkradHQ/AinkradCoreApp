import CoreUI
import SwiftUI

/// The create, told as it happens: the project, its repos, the Brain room and settings, then the Core copying the code.
/// Done steps show a check, the running one breathes with its own bar, later ones wait dimmed. One count per step, from
/// the same numbers the card and the header use: every repo asked for is counted, so a repo the Core refused shows.
struct WizardSetupList: View {
    let creating: CreateProgress?
    let made: ProjectItem?
    let copy: WizardProgress?
    /// The repos the person asked for.
    let requested: Int
    /// Of those, the ones the Core did not add.
    let missed: Int
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var breathe = false

    enum Phase { case waiting, running, done, warn }

    var body: some View {
        let stage = creating?.stage
        let copied = copy?.ready ?? 0
        let copyTotal = made?.repos.count ?? 0
        VStack(alignment: .leading, spacing: Space.s2) {
            row(
                "Create the project", nil, phase: stage == .project ? .running : .done, value: nil,
                symbol: "square.grid.2x2")
            if requested > 0 {
                let added = creating?.added ?? max(0, requested - missed)
                row(
                    "Add the repos", "\(added) of \(requested)",
                    phase: stage == .project ? .waiting : stage == .repos ? .running : missed > 0 ? .warn : .done,
                    value: Double(added) / Double(requested), symbol: "tray.full")
            }
            row(
                "Brain room and settings", nil,
                phase: stage == .finishing ? .running : made != nil && creating == nil ? .done : .waiting,
                value: nil, symbol: "brain")
            if copyTotal > 0 {
                row(
                    "Copy the code", "\(copied) of \(copyTotal)",
                    phase: creating != nil
                        ? .waiting : copy?.settled == true ? ((copy?.failed ?? 0) > 0 ? .warn : .done) : .running,
                    value: Double(copied) / Double(copyTotal), symbol: "arrow.down.doc")
            }
        }
        .padding(Space.s3)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .onAppear { breathe = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup progress")
    }

    private func row(_ title: String, _ count: String?, phase: Phase, value: Double?, symbol: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                switch phase {
                case .done:
                    Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold)
                        .foregroundStyle(.white).transition(.scale.combined(with: .opacity))
                case .warn:
                    Image(systemName: "exclamationmark").coreFont(size: MacTextSize.meta, weight: .bold)
                        .foregroundStyle(.white)
                case .running, .waiting:
                    Image(systemName: symbol).coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(phase == .running ? .white : palette.text2)
                }
            }
            .frame(width: Space.s6, height: Space.s6)
            .background(
                phase == .waiting
                    ? GlassInk.well
                    : phase == .done ? palette.success : phase == .warn ? palette.error : GlassInk.accent(accent),
                in: coreShape(Radius.control)
            )
            // Reduce Motion: the symbol pulse is still, so the running step breathes in opacity instead.
            .opacity(phase == .running && reduce ? (breathe ? 0.7 : 1) : 1)
            .animation(
                phase == .running && reduce ? .easeInOut(duration: Motion.tick).repeatForever(autoreverses: true) : nil,
                value: breathe
            )
            .corePulse(phase == .running)
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack {
                    Text(title).coreFont(size: MacTextSize.body, weight: phase == .running ? .semibold : .regular)
                    Spacer()
                    if let count {
                        Text(count).monospacedDigit().foregroundStyle(palette.text2).contentTransition(.numericText())
                    }
                }
                if phase == .running, let value { CoreMeter(value, label: title).transition(.opacity) }
            }
        }
        .opacity(phase == .waiting ? 0.5 : 1)
        .animation(Motion.out(Motion.ui), value: phase)
    }
}
