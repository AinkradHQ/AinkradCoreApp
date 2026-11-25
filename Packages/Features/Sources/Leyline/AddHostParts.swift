import AppKit
import CoreUI
import SwiftUI

// MARK: parts (the Connections dialog's look, in Leyline's own words)

/// The four steps as a path: a bar and a word each; done and current bars take the accent, the current word is bold.
struct StepPath: View {
    let at: AddHostFlow.Step
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(AddHostFlow.Step.allCases, id: \.self) { s in
                VStack(spacing: Space.s2) {
                    coreShape(2).fill(s <= at ? palette.btnPrimary : GlassInk.track).frame(height: 3)
                    Text(s.title).coreFont(size: MacTextSize.meta, weight: s == at ? .semibold : .regular)
                        .foregroundStyle(s == at ? GlassInk.primary : GlassInk.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Space.s8 * 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at.rawValue + 1) of 4: \(at.title)")
    }
}

/// A key choice: a tile, a name and a line; the chosen one sits on the accent with a tick.
struct KeyOption: View {
    let symbol: String
    let title: String
    let line: String
    let on: Bool
    let pick: () -> Void
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: pick) {
            HStack(spacing: Space.s3) {
                HostTile(symbol: symbol, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
                Spacer(minLength: Space.s2)
                if on { Image(systemName: "checkmark").foregroundStyle(palette.primary).accessibilityHidden(true) }
            }
            .padding(.horizontal, Space.s3 + 2).padding(.vertical, Space.s2 + 2)
            .modifier(SelectedFill(selected: on, hover: hover, radius: Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityLabel("\(title). \(line)")
    }
}

/// "Drop a key file here, or choose one": reads the file's text (a key is small; anything over 64 KB is not a key).
struct DropZone: View {
    let file: String?
    let read: (String, String) -> Void
    @State private var target = false

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: file == nil ? "square.and.arrow.down" : "doc.badge.checkmark")
                .coreFont(size: MacTextSize.large).foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file ?? "Drop a key file here").coreFont(size: MacTextSize.body, weight: .semibold)
                HStack(spacing: Space.s1) {
                    Text("or")
                    Button(file == nil ? "choose one" : "choose another", action: choose).buttonStyle(.link)
                    Text("· id_ed25519, *.pem")
                }
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4 + 2)
        .background(target ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.cardMac))
        .onDrop(of: [.fileURL], isTargeted: $target) { items in
            _ = items.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in load(url) }
            }
            return true
        }
        .animation(Motion.out(Motion.hover), value: target)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 << 10,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        read(url.lastPathComponent, text)
    }
}

/// One line of the check: a numbered tile (a tick once done), a title and a line, and its chip or button.
struct CheckLine<Extra: View>: View {
    let index: Int
    let title: String
    let line: String
    let mark: AddHostFlow.Mark
    var trust: (() -> Void)?
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                coreShape(Radius.control).fill(mark == .running ? GlassInk.wellHover : GlassInk.well)
                if case .done = mark {
                    Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold)
                        .foregroundStyle(GlassInk.green)
                } else if case .failed = mark {
                    Image(systemName: "exclamationmark").coreFont(size: MacTextSize.meta, weight: .bold)
                        .foregroundStyle(GlassInk.redInk)
                } else {
                    Text("\(index)").coreFont(size: MacTextSize.meta, weight: .semibold)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                Text(failure ?? line).coreFont(size: MacTextSize.meta)
                    .foregroundStyle(failure == nil ? GlassInk.secondary : GlassInk.redInk)
                    .fixedSize(horizontal: false, vertical: true)
                extra
            }
            Spacer(minLength: Space.s3)
            if case .done(let chip?) = mark {
                StateBadge(chip, tone: .run, symbol: "checkmark")
            } else if case .asks = mark, let trust {
                Button("Trust It", action: trust).buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
    }

    private var failure: String? {
        if case .failed(let why) = mark { return why }
        return nil
    }
}

extension CheckLine where Extra == EmptyView {
    init(index: Int, title: String, line: String, mark: AddHostFlow.Mark) {
        self.init(index: index, title: title, line: line, mark: mark, trust: nil) { EmptyView() }
    }
}

/// Done: the Core with a green tick that pops in (a fade under Reduce Motion).
struct DonePicture: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        CoreEmblemTile(size: 72)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(GlassInk.green, in: coreShape(Radius.control))
                    .offset(x: Space.s2, y: Space.s2)
                    .scaleEffect(shown || reduce ? 1 : 0.4).opacity(shown ? 1 : 0)
            }
            .padding(.bottom, Space.s2)
            .onAppear { withAnimation(Motion.calm(Motion.press(Motion.move), reduce)) { shown = true } }
            .accessibilityHidden(true)
    }
}
