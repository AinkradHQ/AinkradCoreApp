#if DEBUG && os(macOS)
import SwiftUI

/// Debug gallery section: Apple's own Liquid Glass (SwiftUI, macOS 26 SDK) next to the matching CoreUI component, so we can
/// decide what CoreUI should use. Every official item is labelled with the exact API. Our rules are applied (8 pt rounded
/// rectangles, blue tint only); where a system control cannot follow them it is labelled "system shape — not changeable".
@available(macOS 26, *)
struct OfficialGlassSection: View {
    @Environment(\.colorScheme) var scheme
    @Environment(\.corePalette) var palette
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Namespace var ns
    @State var morphed = false
    @State var union = true
    @State var text = "linux-01"
    @State var secret = "hunter2"
    @State var search = ""
    @State var on = true
    @State var check = true
    @State var level = 0.4
    @State var count = 3
    @State var pick = "all"
    @State var menuPick = "one"
    @State var date = Date(timeIntervalSince1970: 1_793_000_000)
    @State var core = "all"
    @State var coreCheck = true
    @State var popover = false
    @State var sheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Official Liquid Glass").coreFont(size: MacTextSize.large, weight: .semibold)
                Text("Left: Apple's SwiftUI API. Right: the CoreUI component it would replace. Over the Home sky.")
                    .coreFont(size: MacTextSize.body)
                Text("Reduce Transparency makes glass opaque; Reduce Motion turns the morph into a fade.")
                    .coreFont(size: MacTextSize.meta).opacity(0.8)
            }
            actionButtons
            customSurfaces
            inputs
            containers
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { sky }
        .clipShape(coreShape(Radius.pane))
    }

    private var sky: some View {
        ZStack {
            LinearGradient(colors: [palette.surface, palette.bg], startPoint: .top, endPoint: .bottom)
            Image(scheme == .dark ? "HomeSky" : "HomeSkyDay", bundle: .main).resizable().scaledToFill()
        }
    }

    // MARK: Layout helpers

    func group<O: View, C: View>(
        _ title: String, note: String? = nil, @ViewBuilder official: () -> O, @ViewBuilder core: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
            if let note { Text(note).coreFont(size: MacTextSize.meta).opacity(0.8) }
            HStack(alignment: .top, spacing: Space.s6) {
                column("Official", official)
                column("CoreUI", core)
            }
        }
    }

    private func column<C: View>(_ name: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(name).coreFont(size: MacTextSize.meta, weight: .semibold).opacity(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// An item with its API underneath.
    func item<C: View>(_ api: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            content()
            Text(api).coreFont(size: MacTextSize.meta, design: .monospaced).opacity(0.75)
        }
    }

    var rect8: some InsettableShape { coreShape(Radius.control) }
    var blue: Color { palette.primary }

    // MARK: Action buttons

    var actionButtons: some View {
        group(
            "Action buttons",
            note:
                "Apple's default border shape is a capsule; every official button here sets the 8 pt rounded rectangle."
        ) {
            item(".buttonStyle(.glass) + .buttonBorderShape(.roundedRectangle(radius: 8))") {
                HStack {
                    Button("Cancel") {}.buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 8))
                    Button("Save") {}.buttonStyle(.glassProminent).buttonBorderShape(.roundedRectangle(radius: 8))
                }
            }
            item(".glass / .glassProminent, default shape (capsule: breaks our rule)") {
                HStack {
                    Button("Cancel") {}.buttonStyle(.glass)
                    Button("Save") {}.buttonStyle(.glassProminent)
                }
            }
            item(".bordered / .borderedProminent / .borderless / .plain") {
                HStack {
                    Button("Bordered") {}.buttonStyle(.bordered)
                    Button("Prominent") {}.buttonStyle(.borderedProminent)
                    Button("Borderless") {}.buttonStyle(.borderless)
                    Button("Plain") {}.buttonStyle(.plain)
                }
                .buttonBorderShape(.roundedRectangle(radius: 8))
            }
            item(".controlSize(.mini .small .regular .large .extraLarge) on .glassProminent") {
                HStack(alignment: .center) {
                    ForEach([ControlSize.mini, .small, .regular, .large, .extraLarge], id: \.self) { size in
                        Button("\(String(describing: size))") {}.controlSize(size)
                    }
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.roundedRectangle(radius: 8))
            }
            item(".tint(blue) · .disabled(true) · Button(role: .destructive)") {
                HStack {
                    Button("Tinted") {}.tint(blue)
                    Button("Disabled") {}.disabled(true)
                    Button("Delete", role: .destructive) {}
                }
                .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 8))
            }
            item("Label(…).labelStyle(.iconOnly) + .accessibilityLabel · Menu") {
                HStack {
                    Button {
                    } label: {
                        Label("Add", systemImage: "plus").labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Add")
                    Menu("Actions") {
                        Button("Rename") {}
                        Button("Duplicate") {}
                        Button("Delete", role: .destructive) {}
                    }
                }
                .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 8))
            }
        } core: {
            item("CoreButtonStyle(.prominent / .secondary / .plain / .danger)") {
                HStack {
                    Button("Save") {}.buttonStyle(CoreButtonStyle(.prominent))
                    Button("Cancel") {}.buttonStyle(CoreButtonStyle(.secondary))
                    Button("Plain") {}.buttonStyle(CoreButtonStyle(.plain))
                    Button("Delete") {}.buttonStyle(CoreButtonStyle(.danger))
                }
            }
            item("CoreButtonStyle sizes: small / medium / large (no mini, no extraLarge)") {
                HStack {
                    Button("Small") {}.buttonStyle(CoreButtonStyle(.prominent, size: .small))
                    Button("Medium") {}.buttonStyle(CoreButtonStyle(.prominent, size: .medium))
                    Button("Large") {}.buttonStyle(CoreButtonStyle(.prominent, size: .large))
                }
            }
            item("disabled · busy") {
                HStack {
                    Button("Disabled") {}.buttonStyle(CoreButtonStyle(.secondary)).disabled(true)
                    Button("Busy") {}.buttonStyle(CoreButtonStyle(.prominent, busy: true))
                }
            }
            item("Icon-only: Image + .coreGlass() + .accessibilityLabel") {
                Button {
                } label: {
                    Image(systemName: "plus").frame(width: MacSize.controlMd, height: MacSize.controlMd)
                }
                .buttonStyle(.plain).coreGlass().accessibilityLabel("Add")
            }
            item("Menu with CoreButtonStyle(.secondary): no morph") {
                Menu("Actions") {
                    Button("Rename") {}
                    Button("Delete", role: .destructive) {}
                }
                .menuStyle(.button).buttonStyle(CoreButtonStyle(.secondary))
            }
        }
    }
}
#endif
