#if DEBUG
import SwiftUI

extension CoreUIGallery {
    // MARK: Buttons

    @ViewBuilder var buttons: some View {
        GSpec(
            "CoreButtonStyle",
            "One prominent per card. No outlines: a fill step is the hover. The key shows in the tooltip."
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(
                    [
                        ("prominent", CoreButtonKind.prominent), ("secondary", .secondary), ("plain", .plain),
                        ("danger", .danger), ("quietDanger", .quietDanger),
                    ], id: \.0
                ) { name, kind in
                    HStack(spacing: Space.s3) {
                        Text(name).coreFont(size: MacTextSize.meta, design: .monospaced)
                            .foregroundStyle(GlassInk.secondary).frame(width: 96, alignment: .leading)
                        ForEach(galleryStates, id: \.0) { state in
                            Button(state.0) {}.buttonStyle(CoreButtonStyle(kind))
                                .environment(\.coreForcedInteraction, state.1)
                        }
                        Button("Disabled") {}.buttonStyle(CoreButtonStyle(kind)).disabled(true)
                        Button("Busy") {}.buttonStyle(CoreButtonStyle(kind, busy: true))
                    }
                }
            }
        }
        GSpec("CoreButtonSize", "Small for rows, medium by default, large for first run and failure cards.") {
            HStack(spacing: Space.s3) {
                Button("Small") {}.buttonStyle(CoreButtonStyle(.prominent, size: .small))
                Button("Medium") {}.buttonStyle(CoreButtonStyle(.prominent, size: .medium))
                Button("Large") {}.buttonStyle(CoreButtonStyle(.prominent, size: .large))
                Button("Large secondary") {}.coreGlassButton()
                Button("Large danger") {}.coreGlassButton(prominent: true, tint: GlassInk.red)
                Button("With a key") {}.buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.primary)
            }
        }
        GSpec(
            "AppActionTile",
            "A pane header's action: icon and word; prominent for the main one, pulse while something waits."
        ) {
            HStack(spacing: Space.s3) {
                AppActionTile(title: "Sync now", symbol: "arrow.triangle.2.circlepath", key: "⌘R", hue: GlassInk.slate)
                {}
                AppActionTile(title: "New room", symbol: "plus", key: "⌘N", hue: GlassInk.blue, prominent: true) {}
                AppActionTile(title: "Approve", symbol: "hand.raised", key: "", hue: GlassInk.amber, pulse: true) {}
            }
        }
        GSpec("CoreIconButton", "A glyph-only button for chrome: close, split, focus.") {
            HStack(spacing: Space.s3) {
                GVariant("Rest") { CoreIconButton(symbol: "xmark", label: "Close") {} }
                GVariant("Selected") {
                    CoreIconButton(symbol: "rectangle.split.2x1", label: "Split", selected: true) {}
                }
                GVariant("Disabled") { CoreIconButton(symbol: "trash", label: "Delete") {}.disabled(true) }
            }
        }
        GSpec("BackButton", "Back to the list a page came from.") {
            HStack(spacing: Space.s3) {
                ForEach(galleryStates.prefix(3), id: \.0) { s in
                    GVariant(s.0) { BackButton("Runners") {}.environment(\.coreForcedInteraction, s.1) }
                }
            }
        }
        GSpec("CoreQuietPressStyle", "A whole card as a button: a quiet fill on hover, a small press.") {
            HStack(spacing: Space.s3) {
                ForEach(galleryStates.prefix(3), id: \.0) { s in
                    Button {
                    } label: {
                        Text("Runner card \u{00B7} \(s.0)").coreFont(size: MacTextSize.body, weight: .medium)
                            .padding(Space.s4).frame(width: Space.s8 * 5, alignment: .leading)
                            .coreWell(radius: Radius.cardMac)
                    }
                    .buttonStyle(CoreQuietPressStyle(hoverFill: true)).environment(\.coreForcedInteraction, s.1)
                }
            }
        }
        GSpec("CoreKeycap", "A key written out, for help text and the shortcuts list.") {
            HStack(spacing: Space.s2) {
                CoreKeycap("⌘K")
                CoreKeycap("⌥⌘N")
                CoreKeycap("esc")
                CoreKeycap("↩")
            }
        }
    }

    // MARK: Inputs

    @ViewBuilder var inputs: some View {
        GSpec("CoreTextField", "A labelled field. The edge shows only on focus, error or Increase Contrast.") {
            HStack(alignment: .top, spacing: Space.s4) {
                CoreTextField("Rest", placeholder: "Device name", text: $fieldText)
                CoreTextField("Hover", placeholder: "Device name", text: $fieldText)
                    .environment(\.coreForcedInteraction, .hover)
                CoreTextField("Empty", placeholder: "Device name", text: $emptyText)
                CoreTextField("Error", placeholder: "Device name", text: $fieldText, error: "Use 1 to 64 characters.")
                CoreTextField("Disabled", placeholder: "Device name", text: $fieldText).disabled(true)
            }
            HStack(alignment: .top, spacing: Space.s4) {
                CoreTextField("Code", placeholder: "ainkrad-pair:v1?", text: $fieldText, mono: true, suffix: ":443")
                CoreTextField("Large", placeholder: "K7QD", text: $fieldText, mono: true, big: true)
                CoreSecureField("Secure", placeholder: "API key", text: $secret)
            }
        }
        GSpec("CoreTextArea", "Several lines: prompts, notes, keys.") {
            HStack(alignment: .top, spacing: Space.s4) {
                CoreTextArea("Prompt", placeholder: "What should the AI session do?", text: $emptyText)
                CoreTextArea(
                    "Monospaced", placeholder: "-----BEGIN PRIVATE KEY-----", text: $fieldText, design: .monospaced)
                CoreTextArea("Error", placeholder: "Notes", text: $fieldText, error: "Too long.")
            }
        }
        GSpec("CoreSelect", "Pick one of a short list; opens a glass menu.") {
            HStack(alignment: .top, spacing: Space.s4) {
                CoreSelect("Select", selection: $selectPick, options: Self.selectOptions)
                CoreSelect("Hover", selection: $selectPick, options: Self.selectOptions)
                    .environment(\.coreForcedInteraction, .hover)
                CoreSelect("Open", selection: $selectPick, options: Self.selectOptions)
                    .environment(\.coreForcedInteraction, .focused)
                CoreSelect("Error", selection: $selectPick, options: Self.selectOptions, error: "Pick a runner.")
                CoreSelect("Disabled", selection: $selectPick, options: Self.selectOptions).disabled(true)
            }
        }
        GSpec("CoreDropdown", "A menu of actions from a button; destructive items last and red.") {
            HStack(alignment: .top, spacing: Space.s6) {
                CoreDropdown(items: dropItems) { Label("Actions", systemImage: "ellipsis") }
                CoreDropdown(items: dropItems, isPresented: $menuOpen) { Label("Open menu", systemImage: "ellipsis") }
            }
            .frame(height: Space.s8 * 7, alignment: .top)
        }
        GSpec("CoreNumberStepper", "A small count with − and +. Arrow keys when focused.") {
            HStack(spacing: Space.s4) {
                GVariant("Value") { CoreNumberStepper(value: $count, in: 1...8, noun: "AI sessions") }
                GVariant("At the floor") { CoreNumberStepper(value: .constant(1), in: 1...8, noun: "AI sessions") }
                GVariant("At the ceiling") { CoreNumberStepper(value: .constant(8), in: 1...8, noun: "AI sessions") }
                GVariant("Disabled") {
                    CoreNumberStepper(value: .constant(4), in: 1...8, noun: "AI sessions").disabled(true)
                }
            }
        }
        GSpec(
            "GlassSlider", "A value between two named ends. The knob turns to Liquid Glass while dragged."
        ) {
            GlassSlider(value: $slider, low: "See-through", high: "Solid").frame(maxWidth: Space.s8 * 14)
        }
    }

    var dropItems: [CoreDropdownItem] {
        [
            CoreDropdownItem("Rename", symbol: "pencil") {},
            CoreDropdownItem("Move to workspace", symbol: "rectangle.stack", note: "⌘M") {},
            CoreDropdownItem("Pinned", symbol: "pin", checked: true) {},
            CoreDropdownItem("Not available", symbol: "nosign", enabled: false) {},
            CoreDropdownItem("Delete", symbol: "trash", destructive: true) {},
        ]
    }

    // MARK: Selection

    @ViewBuilder var selection: some View {
        GSpec(
            "CoreSwitch",
            "On or off, takes effect at once. Our rounded switch; its knob turns to Liquid Glass while pressed or flipping."
        ) {
            HStack(spacing: Space.s4) {
                CoreSwitch("On", isOn: $switchOn)
                CoreSwitch("Off", isOn: $switchOff)
                CoreSwitch("Hover", isOn: $switchOff).environment(\.coreForcedInteraction, .hover)
                CoreSwitch("Pressed: glass knob", isOn: $switchOn).environment(\.coreForcedInteraction, .pressed)
                CoreSwitch("Disabled on", isOn: .constant(true)).disabled(true)
                CoreSwitch("Disabled off", isOn: .constant(false)).disabled(true)
            }
        }
        GSpec("GlassToggleTile", "A switch with a title and a line, as a whole tile.") {
            HStack(spacing: Space.s3) {
                GlassToggleTile("Notify me", sub: "When an approval waits", symbol: "bell", isOn: $switchOn, fill: true)
                GlassToggleTile("Sound", sub: "Off", symbol: "speaker.wave.2", isOn: $switchOff, fill: true)
            }
        }
        GSpec("CoreCheckbox", "Several may be on at once.") {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(["read", "approve", "terminal"], id: \.self) { name in
                    CoreCheckbox(name, detail: "What this scope allows", isOn: checkBinding(name), mono: true)
                }
                CoreCheckbox("Disabled", detail: "Not available here", isOn: checkBinding("admin")).disabled(true)
            }
        }
        GSpec("RadioRow", "Exactly one of a list.") {
            VStack(spacing: Space.s1) {
                RadioRow("Anthropic", subtitle: "Selected", symbol: "sparkle", selected: choice == "a") { choice = "a" }
                RadioRow("OpenAI", subtitle: "Hover", symbol: "hexagon", selected: false) { choice = "b" }
                    .environment(\.coreForcedInteraction, .hover)
                RadioRow("OpenCode", subtitle: "With a trailing badge", symbol: "terminal", selected: choice == "b") {
                    choice = "b"
                } trailing: {
                    StateBadge("Ready", tone: .run, symbol: "checkmark")
                }
                RadioRow("Google", subtitle: "Disabled", symbol: "globe", selected: false) {}.disabled(true)
            }
            .frame(maxWidth: Space.s8 * 15)
        }
        GSpec("CoreSegmented", "One of a few views of the same thing. Tab to focus, then arrow keys.") {
            let all = [
                CoreSegment("all", "All"), CoreSegment("run", "Running", symbol: "waveform"),
                CoreSegment("done", "Done"),
            ]
            VStack(alignment: .leading, spacing: Space.s3) {
                GVariant("Plain") { CoreSegmented("Filter", segments: all, selection: $segment) }
                GVariant("Fill") {
                    CoreSegmented("Filter", segments: all, selection: $segment, fill: true).frame(
                        maxWidth: Space.s8 * 14)
                }
                GVariant("Disabled") { CoreSegmented("Filter", segments: all, selection: $segment).disabled(true) }
                GVariant("SurfaceModeTabs") { SurfaceModeTabs(mode: $mode) }
            }
        }
        GSpec("AppFilterTile", "A pane header's filter with its count. The key shows in the tooltip.") {
            HStack(spacing: Space.s2) {
                AppFilterTile(title: "Overview", count: -1, on: false, key: "⌘1") {}
                AppFilterTile(title: "Rooms", count: 9, on: true, key: "⌘2") {}
                AppFilterTile(title: "Inbox", count: 10, on: false, key: "⌘3") {}
                AppFilterTile(title: "Hover", count: 1, on: false, key: "⌘4") {}
                    .environment(\.coreForcedInteraction, .hover)
            }
        }
        GSpec("ChoiceTile", "A choice in a confirm card, picked with its number key.") {
            HStack(spacing: Space.s3) {
                ChoiceTile(choice: ConfirmChoice("Keep it", symbol: "tray"), on: true, keys: "1") {}
                ChoiceTile(choice: ConfirmChoice("Move it", symbol: "arrow.right"), on: false, keys: "2") {}
                ChoiceTile(choice: ConfirmChoice("Delete", symbol: "trash", destructive: true), on: false, keys: "3") {}
            }
        }
        GSpec("ScopeTile", "A permission: lit when held, dim when not.") {
            HStack(spacing: Space.s3) {
                ScopeTile(symbol: "eye", name: "Read", detail: "See sessions and logs", hue: GlassInk.blue, on: true)
                ScopeTile(symbol: "terminal", name: "Terminal", detail: "Open a shell", hue: GlassInk.blue, on: false)
            }
        }
    }

    func checkBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { checks.contains(name) },
            set: { if $0 { checks.insert(name) } else { checks.remove(name) } })
    }
}
#endif
