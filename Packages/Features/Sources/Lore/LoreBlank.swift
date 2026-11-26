// LoreBlank — what an empty page shows: a light "Start writing…" where the text will go, three quick starts and
// More… for the rest. Typing hides it at once.
import CoreUI
import LoreEditor
import SwiftUI

extension LoreModel {
    /// Fills the blank page with a template (`LoreTemplates`): a line to write under each empty section, the caret at
    /// the first place to write. The editor's change saves it.
    func start(_ t: LoreTemplate) {
        guard load == .ready, pageBlank else { return }
        pageBlank = false
        if let editor { return editor.insertTemplate(t) }
        page.show(t.markdown, fold: false)
        page.caretToEnd()
        page.focus()
        changed()
    }

    /// More…: every template in a list at the caret (↑ ↓, Return, typing filters, Esc).
    func moreTemplates() { editor?.openTemplates() }
}

/// The quick starts under the first line of the empty page. "Start writing…" itself is drawn by the editor where the
/// caret stands (`LoreEditorController.placeholder`), so the two can never drift apart; this row lines up with the
/// text column through the editor's own `columnInset`.
struct LoreBlankPrompt: View {
    let model: LoreModel
    /// The page's text size: the row sits a line and a gap under the first line.
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let inset = LoreEditorController.columnInset(width: g.size.width)
            // A narrow page drops the words, then stacks the buttons; they never squeeze.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s2) {
                    Text("Or start from").coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                        .fixedSize()
                    buttons
                }
                HStack(spacing: Space.s2) { buttons }
                VStack(alignment: .leading, spacing: Space.s2) { buttons }
            }
            .frame(width: max(0, g.size.width - inset * 2), alignment: .leading)
            .padding(.leading, inset)
            .padding(.top, Space.s6 * 2 + (size * 1.3).rounded())
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Space.s1)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lore-blank")
    }

    @ViewBuilder private var buttons: some View {
        ForEach(LoreTemplates.quick) { t in
            Button {
                model.start(t)
            } label: {
                Label(t.title, systemImage: t.symbol)
            }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .fixedSize()
            .help("Start this note from the \(t.title.lowercased()) template")
        }
        Button("More…") { model.moreTemplates() }
            .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            .fixedSize()
            .help("Every template: daily plan, weekly review, project brief, bug report and more")
            .accessibilityIdentifier("lore-templates-more")
    }
}
