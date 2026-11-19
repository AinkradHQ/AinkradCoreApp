import CoreUI
import SwiftUI

/// The empty workspace (06-workspaces `empty`): says so, counts three seconds and goes Home, unless you stay.
struct EmptyWorkspace: View {
    @Bindable var shell: ShellModel
    @State private var left = 3
    @State private var stayed = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "rectangle.on.rectangle").font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.primary).accessibilityHidden(true)
            Text("This workspace is empty").coreFont(size: MacTextSize.title, weight: .semibold)
            Text(
                stayed
                    ? "Staying here. Open an app with ⌘K to fill it."
                    : "Going back to Home in \(left) \(left == 1 ? "second" : "seconds")."
            )
            .foregroundStyle(palette.text2).monospacedDigit()
            if !stayed {
                GeometryReader { g in
                    coreShape(2).fill(GlassInk.lift(0.12))
                        .overlay(alignment: .leading) {
                            coreShape(2).fill(GlassInk.primary.opacity(0.6))
                                .frame(width: g.size.width * CGFloat(left) / 3)
                        }
                }
                .frame(width: Space.s8 * 5, height: 4)
                // Reduce Motion: the bar steps once a second; otherwise it glides.
                .animation(reduce ? nil : .linear(duration: 1), value: left)
                .accessibilityHidden(true)
                Text("Open an app with ⌘K to keep it.").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            HStack(spacing: Space.s2) {
                if !stayed { Button("Stay here") { stayed = true }.buttonStyle(.coreSecondary) }
                Button {
                    shell.closeEmptySpace()
                } label: {
                    Label("Go Home now", systemImage: "house")
                }
                .buttonStyle(.coreProminent)
            }
        }
        .padding(Space.s5)
        .coreGlass(radius: Radius.pane, interactive: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        // Only counts while the workspace is what is on screen.
        .task(id: shell.surface == .workspace ? shell.currentSpace : nil) {
            left = 3
            stayed = false
            guard shell.surface == .workspace else { return }
            while left > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || stayed { return }
                left -= 1
            }
            shell.closeEmptySpace()
        }
    }
}

/// Bottom of a workspace when there is more than one: where you are and the keys that move you (D-15).
struct SpaceBar: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    static let height = MacSize.controlMd + Space.s3

    var body: some View {
        HStack(spacing: Space.s4) {
            HStack(spacing: Space.s2) {
                ForEach(shell.spaces.indices, id: \.self) { i in
                    Button {
                        shell.switchSpace(to: i)
                    } label: {
                        coreShape(2).fill(GlassInk.primary.opacity(i == shell.spaceIndex ? 0.9 : 0.35))
                            .frame(width: i == shell.spaceIndex ? 16 : 6, height: 6)
                            .frame(minWidth: 16, minHeight: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Workspace \(i + 1) of \(shell.spaces.count)")
                    .accessibilityAddTraits(i == shell.spaceIndex ? .isSelected : [])
                }
            }
            hint("⌃← ⌃→", "Switch")
            hint("⌃1–9", "Jump")
            hint("⌘0", "Home or workspace")
        }
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
        .coreGlass(radius: Radius.cardMac)
        .padding(.bottom, Space.s3)
        .coreAnimation(Motion.out(Motion.ui), value: shell.spaceIndex)
        .accessibilityElement(children: .contain)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: Space.s1) {
            CoreKeycap(keys)
            Text(label).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// ⌃↑: every workspace as a thumbnail to pick from, and a new one.
struct SpaceStrip: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).onTapGesture { shell.spacesOpen = false }
            HStack(spacing: Space.s3) {
                ForEach(shell.spaces.indices, id: \.self) { i in
                    thumb(i)
                }
                Button {
                    shell.spacesOpen = false
                    shell.newSpace()
                } label: {
                    VStack(spacing: Space.s2) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                            .frame(width: Space.s8 * 3, height: Space.s8 * 2)
                        Text("New workspace").coreFont(size: MacTextSize.meta, weight: .medium)
                    }
                    .foregroundStyle(palette.text2)
                }
                .buttonStyle(.coreQuietPress)
            }
            .padding(Space.s3)
            .coreGlass(radius: Radius.pane, interactive: false)
            .transition(.opacity.combined(with: .scale(scale: reduce ? 1 : 0.97)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces")
    }

    private func thumb(_ i: Int) -> some View {
        let on = i == shell.spaceIndex
        let n = max(shell.paneCount(inSpace: i), 1)
        return Button {
            shell.spacesOpen = false
            shell.switchSpace(to: i)
        } label: {
            VStack(spacing: Space.s2) {
                HStack(spacing: 3) {
                    ForEach(0..<n, id: \.self) { _ in coreShape(Radius.chip).fill(GlassInk.lift(on ? 0.3 : 0.16)) }
                }
                .padding(Space.s1)
                .frame(width: Space.s8 * 3, height: Space.s8 * 2)
                .background(GlassInk.lift(on ? 0.1 : 0.04), in: coreShape(Radius.control))
                HStack(spacing: Space.s1) {
                    Text("Workspace \(i + 1)").coreFont(size: MacTextSize.meta, weight: on ? .semibold : .regular)
                    if i < 9 { CoreKeycap("⌃\(i + 1)") }
                }
                .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
            }
        }
        .buttonStyle(.coreQuietPress)
        .accessibilityLabel("Workspace \(i + 1), \(shell.paneCount(inSpace: i)) apps")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Why this app is in a workspace of its own, said once (06-workspaces `new-space`).
struct SpaceNoteCard: View {
    @Bindable var shell: ShellModel
    let note: SpaceNote
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(note.fullScreen ? "\(note.app) opened in its own workspace" : "\(note.app) did not fit, so it has a workspace")
                .coreFont(size: MacTextSize.body, weight: .semibold)
            Text(
                (note.fullScreen
                    ? "\(note.app) needs the whole screen, so it did not squeeze in beside your other apps."
                    : "There was no room beside your other apps, so \(note.app) did not squeeze in.")
                    + " Press ⌃← to go back to Workspace \(note.backTo)."
            )
            .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Don't show this again") { shell.dismissSpaceNote(forever: true) }.buttonStyle(.corePlain)
                Spacer()
                Button("Got it") { shell.dismissSpaceNote(forever: false) }.buttonStyle(.coreProminent)
            }
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 11)
        .coreGlass(radius: Radius.pane, interactive: false)
        .padding(.bottom, SpaceBar.height + Space.s4)
        .accessibilityElement(children: .contain)
    }
}
