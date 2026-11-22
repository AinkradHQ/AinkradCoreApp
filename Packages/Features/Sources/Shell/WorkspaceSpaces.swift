import CoreUI
import SwiftUI

/// Top bar, beside the right icons (Ahmed, 2026-11-21: no bottom bar): one small rounded bar per workspace, the current one
/// longer and lit. A click opens the overview; hover help names the keys.
struct SpaceIndicator: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let n = shell.spaces.count
        let at = shell.spaceIndex
        Button {
            shell.toggleSpaces()
        } label: {
            HStack(spacing: 3) {
                ForEach(0..<min(n, 9), id: \.self) { i in
                    coreShape(2).fill(palette.text.opacity(i == at ? 0.9 : 0.35))
                        .frame(width: i == at ? 14 : 6, height: 6)
                }
            }
            .padding(.horizontal, Space.s2)
            .frame(minWidth: 36, minHeight: MacSize.controlMd - Space.s1 / 2)
        }
        .buttonStyle(StatusBarStyle(on: shell.overviewOpen))
        .coreAnimation(Motion.out(Motion.ui), value: at)
        .coreAnimation(Motion.out(Motion.ui), value: n)
        .help("Workspace \(at + 1) of \(n) · ⌃← ⌃→ switch · ⌃1–9 jump · ⌃↑ all workspaces")
        .accessibilityLabel("Workspace \(at + 1) of \(n)")
        .accessibilityHint("Shows all workspaces")
    }
}
