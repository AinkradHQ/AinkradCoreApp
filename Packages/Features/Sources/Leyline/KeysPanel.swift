import CoreUI
import SwiftUI

/// The Keys panel: slides in over the right of the map or the list, the pane's full height, the map usable beside it. Two
/// tiles at the top open Generate (⌘G) and Import (⌘I) in place; below them the keys the Core keeps sealed, newest first,
/// one row each (a selected row opens), and the host keys it pinned. A key file dropped anywhere on the panel opens Import
/// with it. ↑ ↓ open the next key, ⌘C copies its public key, Esc closes the form, then the panel.
struct KeysPanel: View {
    static let width: CGFloat = 380
    let model: LeylineModel
    @State private var knownOpen = true
    @State private var dropping = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var canWrite: Bool { !model.readOnly && model.load == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    tiles
                    if let form = model.keyForm {
                        Group {
                            switch form {
                            case .generate: GenerateKeyForm(model: model)
                            case .importing: ImportKeyForm(model: model, dropping: dropping)
                            }
                        }
                        .padding(Space.s3)
                        .coreWell(radius: Radius.cardMac)
                        .transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s2)))
                    }
                    if model.keys.isEmpty { empty } else { keys }
                    known
                }
                .padding(.bottom, Space.s1)
            }
            .scrollIndicators(.automatic)
            Text("⌘G generate · ⌘I import · ↑↓ open · ⌘C copy · esc close")
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        // One ease for the forms and the rows opening: the height follows; a fade only under Reduce Motion.
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: model.keyForm)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: model.keySelected)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: model.keyDraft.text.isEmpty)
        .frame(width: Self.width - Space.s4 * 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .corePanel(radius: Radius.pane, padding: Space.s4)
        .contentShape(coreShape(Radius.pane))
        .background { shortcuts }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { items in
            guard canWrite else { return false }
            _ = items.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.importKeyFile(url) }
            }
            return true
        }
        .onChange(of: dropping) { _, on in
            if on, canWrite, model.keyForm != .importing { model.openKeyForm(.importing) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keys")
        .accessibilityIdentifier("leyline-keys")
    }

    /// ⌘C copies the open key's public key while no form is open (a form's fields keep their own ⌘C).
    @ViewBuilder private var shortcuts: some View {
        if model.keyForm == nil, let id = model.keySelected, let k = model.keys.first(where: { $0.id == id }) {
            Button("Copy Public Key") { model.copyPublicKey(k) }
                .keyboardShortcut("c", modifiers: .command).opacity(0).accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text("Keys").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if !model.keys.isEmpty {
                Text("\(model.keys.count) sealed in your Core").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: Space.s2)
            Button("esc") { model.closeKeys() }
                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                .help("Close Keys (esc)")
                .accessibilityLabel("Close Keys")
        }
    }

    private var tiles: some View {
        HStack(spacing: Space.s2) {
            KeyActionTile(
                symbol: "plus", title: "Generate", line: "Made in your Core", key: "g",
                on: model.keyForm == .generate
            ) { model.openKeyForm(.generate) }
            .accessibilityIdentifier("leyline-generate-key")
            KeyActionTile(
                symbol: "square.and.arrow.down", title: "Import", line: "Drop or choose a file", key: "i",
                on: model.keyForm == .importing
            ) { model.openKeyForm(.importing) }
            .accessibilityIdentifier("leyline-import-key")
        }
        .disabled(!canWrite)
    }

    private var keys: some View {
        VStack(spacing: Space.s2) {
            ForEach(model.keyList) { KeyRow(model: model, key: $0) }
        }
    }

    private var empty: some View {
        CoreStateCard(
            symbol: "key", title: "No keys yet",
            line:
                "Kept sealed in your Core. Hosts sign in with them; nobody sees them again. Drop a key file here to import it."
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var known: some View {
        if !model.knownHosts.isEmpty {
            Button {
                withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { knownOpen.toggle() }
            } label: {
                HStack(spacing: Space.s1 + 2) {
                    Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .rotationEffect(.degrees(knownOpen ? 0 : -90))
                    Text("Known hosts · \(model.knownHosts.count) pinned").coreFont(size: MacTextSize.meta + 1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(GlassInk.secondary).contentShape(Rectangle())
            }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.control))
            .padding(.top, Space.s2)
            .help(knownOpen ? "Hide the pinned host keys" : "Show the pinned host keys")
            .accessibilityValue(knownOpen ? "shown" : "hidden")
            .accessibilityIdentifier("leyline-known-hosts")
            if knownOpen {
                VStack(spacing: Space.s1) {
                    ForEach(model.knownHosts) { KnownHostRow(model: model, known: $0) }
                }
                .transition(.opacity)
            }
        }
    }
}

/// One of the two actions at the top of the panel, built like Connections' pick card: an `IconTile`, a title, a line, its
/// key in the corner (`CoreKeycap`). Lit (`SelectedFill`) while its form is open; a second press closes the form.
struct KeyActionTile: View {
    let symbol: String
    let title: String
    let line: String
    let key: Character
    let on: Bool
    let run: () -> Void
    @State private var hover = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        Button(action: run) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top) {
                    IconTile(symbol, hue: palette.btnPrimary, size: Space.s6 + Space.s1, bounce: on)
                    Spacer(minLength: Space.s2)
                    CoreKeycap("⌘\(key.uppercased())")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SelectedFill(selected: on, hover: hover, radius: Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac))
        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        .onHover { hover = $0 }
        .animation(Motion.out(Motion.hover), value: hover)
        .help("\(title) (⌘\(key.uppercased())) · needs Touch ID")
        .accessibilityLabel(title)
        .accessibilityHint(line)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
