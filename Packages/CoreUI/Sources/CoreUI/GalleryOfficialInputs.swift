#if DEBUG && os(macOS)
import AppKit
import SwiftUI

/// The system search field (`.searchable` only draws in a window toolbar, so it cannot sit inline in the gallery).
private struct SystemSearchField: NSViewRepresentable {
    func makeNSView(context: Context) -> NSSearchField { NSSearchField() }
    func updateNSView(_ view: NSSearchField, context: Context) { view.placeholderString = "Search" }
}

@available(macOS 26, *)
extension OfficialGlassSection {
    var inputs: some View {
        group(
            "Inputs",
            note:
                "System fields, switches and sliders draw their own shapes: where one cannot be 8 pt rounded it says so."
        ) {
            item("TextField .roundedBorder · SecureField .roundedBorder") {
                VStack(alignment: .leading) {
                    TextField("Device name", text: $text)
                    SecureField("Passphrase", text: $secret)
                }
                .textFieldStyle(.roundedBorder)
            }
            item("NSSearchField (system search; .searchable lives in the toolbar only)") {
                SystemSearchField().frame(height: 24)
            }
            item("Toggle .switch (system shape — not changeable) · .checkbox") {
                HStack(spacing: Space.s4) {
                    Toggle("Switch", isOn: $on).toggleStyle(.switch)
                    Toggle("Checkbox", isOn: $check).toggleStyle(.checkbox)
                }
            }
            item("Slider · Stepper (system shape — not changeable)") {
                HStack(spacing: Space.s4) {
                    Slider(value: $level).frame(maxWidth: 160)
                    Stepper("Count \(count)", value: $count)
                }
            }
            item("Picker .segmented · .menu") {
                HStack(spacing: Space.s4) {
                    Picker("Filter", selection: $pick) {
                        Text("All").tag("all")
                        Text("Running").tag("run")
                        Text("Done").tag("done")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Picker("Pick", selection: $menuPick) {
                        Text("One").tag("one")
                        Text("Two").tag("two")
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
            }
            item("DatePicker .compact") {
                DatePicker("Due", selection: $date).datePickerStyle(.compact)
            }
        } core: {
            item("CoreTextField · CoreSecureField") {
                VStack(alignment: .leading, spacing: Space.s3) {
                    CoreTextField("Name", placeholder: "Device name", text: $text)
                    CoreSecureField("Passphrase", placeholder: "Passphrase", text: $secret)
                }
            }
            item("CoreCheckbox (also the only toggle CoreUI has)") {
                CoreCheckbox("Allow terminal", detail: "What this scope allows", isOn: $coreCheck)
            }
            item("CoreSegmented") {
                CoreSegmented(
                    "Filter",
                    segments: [CoreSegment("all", "All"), CoreSegment("run", "Running"), CoreSegment("done", "Done")],
                    selection: $core)
            }
            Text("No CoreUI search field, switch, slider, stepper, menu picker or date picker.")
                .coreFont(size: MacTextSize.meta).opacity(0.8)
        }
    }

    var containers: some View {
        group(
            "Containers",
            note:
                "Sheets, popovers, forms and toolbars take system glass on their own: no custom background behind them."
        ) {
            item("Form + .formStyle(.grouped), Section") {
                Form {
                    Section("Device") {
                        TextField("Name", text: $text)
                        Toggle("Allow terminal", isOn: $on)
                    }
                }
                .formStyle(.grouped).scrollDisabled(true).frame(height: 150)
            }
            item("List row (.listStyle(.inset))") {
                List {
                    Label("linux-01", systemImage: "terminal")
                    Label("linux-02", systemImage: "terminal")
                }
                .listStyle(.inset).scrollDisabled(true).frame(height: 70)
            }
            item(".popover(isPresented:) · .sheet(isPresented:)") {
                HStack {
                    Button("Popover") { popover = true }
                        .popover(isPresented: $popover) { Text("Popover content").padding(Space.s4) }
                    Button("Sheet") { sheet = true }
                        .sheet(isPresented: $sheet) {
                            VStack(spacing: Space.s4) {
                                Text("System sheet").font(.headline)
                                Button("Done") { sheet = false }.buttonStyle(.glassProminent)
                            }
                            .padding(Space.s6).frame(width: 280)
                        }
                }
                .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 8))
            }
            item("Toolbar group: GlassEffectContainer + fixed gap (ToolbarSpacer(.fixed) is toolbar-only, not inline)")
            {
                GlassEffectContainer(spacing: Space.s4) {
                    HStack(spacing: Space.s1) {
                        ForEach(["sidebar.left", "square.and.pencil"], id: \.self) { name in
                            Image(systemName: name).frame(width: 32, height: 28)
                                .glassEffect(.regular, in: .rect(cornerRadius: 8))
                        }
                        Spacer().frame(width: Space.s4)
                        Image(systemName: "gearshape").frame(width: 32, height: 28)
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                }
            }
            item(".scrollEdgeEffectStyle(.soft | .hard, for: .top) under a glass bar") {
                HStack {
                    edgeDemo(.soft)
                    edgeDemo(.hard)
                }
            }
        } core: {
            item("CoreRow in a VStack (no list, no form)") {
                VStack(spacing: Space.s2) {
                    CoreRow("linux-01", subtitle: "Running", symbol: "terminal", action: {})
                    CoreRow("linux-02", subtitle: "Selected", symbol: "terminal", selected: true, action: {})
                }
            }
            item("CoreSheet content (inside the system .sheet)") {
                CoreSheet("Rename device") {
                    Text("Shown here inline; the system sheet frames it.")
                } footer: {
                    Button("Done") {}.buttonStyle(CoreButtonStyle(.prominent))
                }
                .corePanel()
            }
            Text("CoreUI has no popover, toolbar group or scroll-edge effect.")
                .coreFont(size: MacTextSize.meta).opacity(0.8)
        }
    }

    private func edgeDemo(_ style: ScrollEdgeEffectStyle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(0..<12, id: \.self) { Text("Row \($0 + 1) of scrolling content") }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s2)
        }
        .scrollEdgeEffectStyle(style, for: .top)
        .safeAreaInset(edge: .top) {
            Text(style == .soft ? "soft" : "hard").padding(.horizontal, Space.s3).padding(.vertical, Space.s1)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
        .frame(height: 120).clipShape(coreShape(Radius.control))
    }
}
#endif
