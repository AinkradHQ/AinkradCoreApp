import CoreUI
import SwiftUI

/// A brand kit (or folder) opened: its colours, fonts and files, each added and removed in place. Colours and fonts are
/// written as whole lists (the Core replaces them); files one at a time with an optional role. A folder only holds files.
struct BrandKitEditor: View {
    let model: DesignModel
    let kit: BrandKit
    @State private var colour = ""
    @State private var picked = Color.gray
    @State private var error: String?
    @State private var addFont = false
    @State private var addFile = false
    @Environment(\.coreAccent) private var paneAccent

    private var locked: Bool { model.readOnly }
    private var isKit: Bool { kit.kind == .brandKit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(spacing: Space.s3) {
                    Text(kit.name).coreFont(size: MacTextSize.large, weight: .semibold).lineLimit(1)
                    Button("Rename…") { model.askRename(.kit(kit)) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(locked)
                    Spacer(minLength: 0)
                }
                if let error { CoreFieldError(error) }
                if isKit {
                    colours
                    fonts
                }
                files
            }
            .padding(Space.s6).frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .accessibilityIdentifier("design-kit-editor")
    }

    private func section<C: View>(_ title: String, _ sub: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
            Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            content()
        }
    }

    private func run(_ work: @escaping () async -> String?) {
        error = nil
        Task { error = await work() }
    }

    // MARK: colours

    private var colours: some View {
        section("Colours", "\(Words.count(kit.colors.count, "colour")). Each is #rrggbb.") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Space.s8 * 5), spacing: Space.s2)], alignment: .leading,
                spacing: Space.s2
            ) {
                ForEach(kit.colors, id: \.self) { hex in
                    HStack(spacing: Space.s2) {
                        Swatch(hex: hex).frame(width: Space.s6, height: Space.s5)
                        Text(hex.uppercased()).coreFont(size: MacTextSize.meta).monospaced().lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                        if !locked {
                            CoreIconButton(symbol: "xmark", label: "Remove \(hex)") {
                                run { await model.editKit(kit, colors: kit.colors.filter { $0 != hex }) }
                            }
                        }
                    }
                    .padding(Space.s1).background(GlassInk.well, in: coreShape(Radius.control))
                }
            }
            if !locked {
                HStack(alignment: .bottom, spacing: Space.s2) {
                    ColorPicker("Pick a colour", selection: $picked, supportsOpacity: false).labelsHidden()
                        .onChange(of: picked) { _, c in
                            colour = ColorField.hex(c).flatMap(DesignLibrary.kitColor) ?? colour
                        }
                    CoreTextField("Add a colour", placeholder: "#e3a857", text: $colour, mono: true) { addColour() }
                        .frame(maxWidth: Space.s8 * 6)
                    Button("Add") { addColour() }.buttonStyle(CoreButtonStyle(.secondary))
                        .disabled(DesignLibrary.kitColor(colour) == nil)
                        .help("Type a hex colour like #e3a857 or pick one")
                }
            }
        }
    }

    private func addColour() {
        guard let hex = DesignLibrary.kitColor(colour) else {
            error = "A colour looks like #e3a857."
            return
        }
        colour = ""
        if kit.colors.contains(hex) { return }
        run { await model.editKit(kit, colors: kit.colors + [hex]) }
    }

    // MARK: fonts

    private var fonts: some View {
        let library = model.assets.filter { $0.kind == .font && !kit.fonts.contains($0.sha) }
        return section("Fonts", "Font files from the library; they are checked by the Core before use.") {
            ForEach(kit.fonts, id: \.self) { sha in
                let f = model.asset(sha)
                CoreRow(
                    f?.name ?? "A removed font",
                    subtitle: f.map { $0.check == .ok ? "Checked" : $0.check == .pending ? "Checking…" : "Refused" },
                    symbol: "textformat"
                ) {
                    if !locked {
                        CoreIconButton(symbol: "xmark", label: "Remove the font") {
                            run { await model.editKit(kit, fonts: kit.fonts.filter { $0 != sha }) }
                        }
                    }
                }
            }
            CoreDropdown(
                items: library.prefix(40).map { f in
                    CoreDropdownItem(f.name, symbol: "textformat") {
                        run { await model.editKit(kit, fonts: kit.fonts + [f.sha]) }
                    }
                }, isPresented: $addFont
            ) { Label("Add a font", systemImage: "plus") }
            .disabled(library.isEmpty || locked)
            .help(library.isEmpty ? "Upload a font to the library first" : "Put a library font in this kit")
        }
    }

    // MARK: files

    private static let roles = ["logo", "mark", "wordmark", "app icon", "icon"]

    private var files: some View {
        let library = model.assets.filter { a in a.kind != .font && !kit.items.contains { i in i.sha == a.sha } }
        return section(
            "Files", "Logos, icons and pictures this \(isKit ? "kit" : "folder") holds. A role says what each is for."
        ) {
            if kit.items.isEmpty { Text("Nothing in it yet.").foregroundStyle(GlassInk.secondary) }
            ForEach(kit.items, id: \.sha) { i in
                if let a = model.asset(i.sha) {
                    CoreRow(
                        a.name, subtitle: i.role ?? DesignItem.asset(a).kindWord, symbol: DesignItem.asset(a).symbol,
                        action: { model.openItem(DesignItem.asset(a).id) }
                    ) {
                        if !locked {
                            RoleMenu(role: i.role, roles: Self.roles) { r in
                                run { await model.putKitItem(kit, sha: i.sha, role: r) }
                            }
                            CoreIconButton(
                                symbol: "xmark", label: "Remove \(a.name) from the \(isKit ? "kit" : "folder")"
                            ) {
                                run { await model.removeKitItem(kit, sha: i.sha) }
                            }
                        }
                    }
                }
            }
            CoreDropdown(
                items: library.prefix(40).map { a in
                    CoreDropdownItem(a.name, symbol: DesignItem.asset(a).symbol, note: DesignItem.asset(a).kindWord) {
                        run { await model.putKitItem(kit, sha: a.sha, role: nil) }
                    }
                }, isPresented: $addFile
            ) { Label("Add a file", systemImage: "plus") }
            .disabled(library.isEmpty || locked)
            .help(
                library.isEmpty
                    ? "Upload files to the library first" : "Put a library file in this \(isKit ? "kit" : "folder")")
        }
    }
}

/// A file's role in a kit: a small menu with a few common words and none.
private struct RoleMenu: View {
    let role: String?
    let roles: [String]
    let pick: (String?) -> Void
    @State private var open = false

    var body: some View {
        CoreDropdown(
            items: roles.map { r in CoreDropdownItem(r.capitalizedFirst, checked: r == role) { pick(r) } }
                + [CoreDropdownItem("No role", checked: role == nil) { pick(nil) }],
            isPresented: $open
        ) { Text(role?.capitalizedFirst ?? "Role").coreFont(size: MacTextSize.meta) }
        .help("What this file is for in the kit")
    }
}
