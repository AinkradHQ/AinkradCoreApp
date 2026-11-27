import CoreUI
import SwiftUI

/// About, editable: the design system a design follows, and a file's tags.

/// "System": which design system a design follows. None unlinks it.
struct DocSystemPicker: View {
    let model: DesignModel
    let doc: DesignDoc

    private var systems: [DesignDoc] { model.docs.filter { $0.kind == .system } }

    /// The choices: None, every system, and the linked one when the list no longer has it (archived or removed).
    static func options(systems: [DesignDoc], current: String?) -> [CoreSelectOption<String>] {
        var out = [CoreSelectOption("", "None")] + systems.map { CoreSelectOption($0.id, $0.name) }
        if let c = current, !systems.contains(where: { $0.id == c }) {
            out.append(CoreSelectOption(c, "An archived system"))
        }
        return out
    }

    var body: some View {
        CoreSelect(
            "System",
            selection: Binding(
                get: { doc.system ?? "" },
                set: { new in
                    guard new != (doc.system ?? "") else { return }
                    Task { await model.setSystem(doc, new.isEmpty ? nil : new) }
                }),
            options: Self.options(systems: systems, current: doc.system)
        )
        .disabled(model.readOnly)
        .help(
            model.readOnly ? "This device can look at designs but not change them." : "The tokens this design follows"
        )
        .padding(.vertical, Space.s1)
        .accessibilityIdentifier("design-system-picker")
    }
}

/// A file's tags as chips with a remove each, and a field to add more (comma-separated).
struct AssetTagsEditor: View {
    let model: DesignModel
    let asset: DesignAsset
    @State private var text = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if asset.tags.isEmpty {
                Text("No tags yet.").foregroundStyle(GlassInk.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Space.s8 * 2), spacing: Space.s1)], alignment: .leading,
                    spacing: Space.s1
                ) {
                    ForEach(asset.tags, id: \.self) { t in
                        HStack(spacing: Space.s1) {
                            Text(t).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(1)
                            Spacer(minLength: 0)
                            if !model.readOnly {
                                CoreIconButton(symbol: "xmark", label: "Remove the tag \(t)") {
                                    save(asset.tags.filter { $0 != t })
                                }
                            }
                        }
                        .padding(.leading, Space.s2).frame(minHeight: MacSize.chip)
                        .background(GlassInk.well, in: coreShape(Radius.control))
                    }
                }
            }
            if !model.readOnly {
                CoreTextField("Add tags", placeholder: "logo, dark", text: $text) { add() }
                    .disabled(busy)
            }
            if let error { CoreFieldError(error) }
        }
        .accessibilityIdentifier("design-asset-tags")
    }

    private func add() {
        let r = DesignLibrary.tags(from: (asset.tags + [text]).joined(separator: ","))
        if let e = r.error {
            error = e
            return
        }
        guard r.tags != asset.tags else {
            text = ""
            return
        }
        save(r.tags)
    }

    private func save(_ tags: [String]) {
        busy = true
        error = nil
        Task {
            error = await model.setTags(asset, tags)
            if error == nil { text = "" }
            busy = false
        }
    }
}
