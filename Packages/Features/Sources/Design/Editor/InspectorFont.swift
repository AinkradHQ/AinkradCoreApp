import CoreUI
import SwiftUI

/// The font of a text layer: System, or a font from the library. A font file goes to the canvas by its hash, so only
/// library fonts can be chosen; installed fonts need adding to the library first.
struct FontRow: View {
    @Bindable var editor: DesignEditor
    let node: EditorNode

    var body: some View {
        let t = node.props["type"]
        let current = FontChoice.sha(of: t?["font"])
        let fonts = editor.libraryFonts
        CoreSelect(
            "Font",
            selection: Binding(
                get: { current ?? "" },
                set: { sha in
                    let name = fonts.first { $0.sha == sha }?.name ?? ""
                    editor.set(
                        "type",
                        InspectorEdits.type(node, "font", FontChoice.value(sha: sha.isEmpty ? nil : sha, name: name)))
                }),
            options: [CoreSelectOption("", "System", symbol: "textformat")]
                + fonts.map { CoreSelectOption($0.sha, FontChoice.family($0.name), symbol: "textformat") }
                + missing(current, fonts))
        if fonts.isEmpty {
            Text(
                "Add a font file to the library (Fonts) to use it here. Installed fonts are not drawn unless they are in the library."
            )
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A font the layer names that the library does not list (removed, or not loaded yet): kept, so it is not lost.
    private func missing(_ sha: String?, _ fonts: [DesignAsset]) -> [CoreSelectOption<String>] {
        guard let sha, !fonts.contains(where: { $0.sha == sha }) else { return [] }
        let name = node.props["type"]?["font"]?["family"]?.string ?? "Font"
        return [CoreSelectOption(sha, name, note: "not in the library")]
    }
}
