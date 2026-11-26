import CoreUI
import Projects
import SwiftUI

/// An open design with its canvas (V3-04): layers at the left, the canvas in the middle with the Ask… field floating over
/// its foot, the inspector at the right. Each is an island over the pane's surface, like the Projects space; the canvas
/// keeps the stage well it had. All of it is native SwiftUI around the engine's view (D8).
struct EditorStage: View {
    let model: DesignModel
    let item: DesignItem
    let editor: DesignEditor
    let canvas: AnyView

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            LayersIsland(editor: editor).frame(width: Space.s8 * 9)
            ZStack(alignment: .bottom) {
                canvas
                    .overlay {
                        if let c = model.composer, c.phase == .drawing, !c.busyRects.isEmpty {
                            CanvasAIOverlay(editor: editor, rects: c.busyRects, editing: c.editing)
                                .transition(.opacity)
                        }
                    }
                    .clipShape(coreShape(Radius.pane))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contextMenu { DesignMenu(model: model, item: item) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("design-canvas")
                VStack(spacing: Space.s2) {
                    if editor.syncStuck {
                        CoreNotice(symbol: "exclamationmark.triangle", title: DesignEditor.stuckSentence, tone: .warn)
                            .frame(maxWidth: Space.s8 * 14)
                    } else if let note = editor.notice {
                        CoreNotice(symbol: "exclamationmark.triangle", title: note, tone: .warn) {
                            Button("Dismiss") { editor.notice = nil }.buttonStyle(.corePlain)
                        }
                        .frame(maxWidth: Space.s8 * 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Spacer(minLength: 0)
                    if let c = model.composer, case .doc(let d) = item, c.doc == d.id {
                        DesignAIPanel(composer: c)
                            .transition(
                                .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.97)))
                    }
                    CanvasToolbar(model: model, editor: editor)
                }
                .animation(Motion.out(Motion.ui), value: editor.notice)
                .animation(Motion.out(Motion.ui), value: model.composer == nil)
                .padding(Space.s4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coreWell(radius: Radius.pane)
            Island("Inspector") { InspectorIsland(editor: editor) }.frame(width: Space.s8 * 10)
        }
    }
}
