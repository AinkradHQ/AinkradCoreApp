import CoreUI
import SwiftUI

/// The Brain dropdown (mockup `kit/topbar.js` `brain()`): how it is, the Collect, Distill, Remember flow with what it does now,
/// the five areas that open Brain, and what it learned today with an Undo. An older Core gets the counts it has.
struct BrainPanel: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let glance = shell.brainGlance?()
        return VStack(alignment: .leading, spacing: Space.s3) {
            if let g = glance {
                DropHead(
                    symbol: "brain", title: "Brain", meta: g.status,
                    badge: DropBadge(g.healthy ? "Healthy" : "Needs a look", tone: g.healthy ? .done : .warn))
                if let i = g.importing { importing(i) }
                if g.doing != nil || g.flowStep != nil { doing(g) }
                if !g.stats.isEmpty {
                    HStack(spacing: Space.s2) { ForEach(g.stats) { stat($0) } }
                }
                if g.learned > 0 { learned(g.learned) }
            } else {
                DropHead(
                    symbol: "brain", title: "Brain", meta: "Not ready yet", badge: DropBadge("Waiting", tone: .queue))
            }
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                if glance != nil, glance?.importing == nil, shell.brainOpenImport != nil {
                    Button {
                        openImport()
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .accessibilityIdentifier("brain-drop-import")
                }
                Button("Open Brain") { open(nil) }.buttonStyle(CoreButtonStyle(.prominent))
            }
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 13)
        .corePanel(radius: Radius.pane, padding: 0, part: .popups)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Brain")
        .task { await shell.brainRefresh?() }
    }

    private func doing(_ g: BrainGlance) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Doing now").coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
            if let step = g.flowStep { flow(step) }
            if let doing = g.doing { Text(doing).coreFont(size: MacTextSize.headline, weight: .semibold) }
            if let p = g.progress { CoreMeter(p, label: "Brain progress") }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
    }

    /// An import under way: its step, how far, and the way back into its panel.
    private func importing(_ i: BrainGlance.Importing) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Importing… \(i.step)").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(palette.text2)
                Spacer(minLength: Space.s2)
                if let d = i.detail {
                    Text(d).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).monospacedDigit()
                }
            }
            Text(i.line).coreFont(size: MacTextSize.headline, weight: .semibold)
            if let p = i.progress { CoreMeter(p, label: "Import progress") } else { CoreBusyBar() }
            HStack {
                Spacer(minLength: 0)
                Button("Open import") { openImport() }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .accessibilityIdentifier("brain-drop-open-import")
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-drop-importing")
    }

    private func openImport() {
        shell.topMenu = nil
        shell.brainOpenImport?()
    }

    private static let steps: [(String, String)] = [
        ("Collect", "magnifyingglass"), ("Distill", "sparkles"), ("Remember", "externaldrive"),
    ]

    private func flow(_ now: Int) -> some View {
        HStack(spacing: Space.s2) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: Space.s1) {
                    Image(systemName: i < now ? "checkmark" : s.1).font(
                        .system(size: MacTextSize.meta, weight: .semibold)
                    )
                    .foregroundStyle(
                        i == now ? palette.tone(.run).ink : i < now ? palette.tone(.done).ink : palette.text2)
                    Text(s.0).coreFont(size: MacTextSize.meta, weight: i == now ? .semibold : .regular)
                        .foregroundStyle(i > now ? palette.text2 : palette.text)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(s.0), \(i < now ? "done" : i == now ? "now" : "next")")
                if i < Self.steps.count - 1 {
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(palette.text2)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func stat(_ s: BrainGlance.Stat) -> some View {
        Button {
            open(s.area)
        } label: {
            DropStat("\(s.count)", s.label)
        }
        .buttonStyle(.plain)
        .accessibilityHint(s.area == nil ? "" : "Opens \(s.label) in Brain")
    }

    private func learned(_ n: Int) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "sparkles").foregroundStyle(palette.tone(.run).ink).accessibilityHidden(true)
            (Text("Learned today").fontWeight(.semibold) + Text(" · \(n) new \(n == 1 ? "thing" : "things")"))
                .coreFont(size: MacTextSize.body).lineLimit(1)
            Spacer(minLength: Space.s2)
            Button("Undo") { shell.brainUndoLearned?() }.buttonStyle(CoreButtonStyle(.plain, size: .small))
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
    }

    private func open(_ area: String?) {
        shell.topMenu = nil
        if let area, let go = shell.brainOpenArea { go(area) } else { shell.launcher.entry("brain")?.run() }
    }
}
