import CoreUI
import Projects
import Shell
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
                    // Reopen: a new id builds a new canvas, so a new engine and socket.
                    .id(editor.generation)
                    .overlay {
                        // Mounted for the panel's life and faded by `active`: a removal transition over the canvas
                        // never finished (the timeline kept it alive), so the shimmer stayed after Done.
                        if let c = model.composer, !c.busyRects.isEmpty {
                            CanvasAIOverlay(
                                editor: editor, rects: c.busyRects, editing: c.editing, active: c.phase == .drawing)
                        }
                    }
                    .overlay {
                        if !editor.loaded { CanvasLoading(editor: editor).transition(.opacity) }
                    }
                    .overlay(alignment: .top) {
                        if editor.loaded, !editor.syncConnected, !editor.syncHalted {
                            CanvasReconnecting(editor: editor).padding(Space.s3).transition(.opacity)
                        }
                    }
                    .animation(Motion.out(Motion.ui), value: editor.syncConnected)
                    .animation(Motion.out(Motion.ui), value: editor.loaded)
                    .clipShape(coreShape(Radius.pane))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contextMenu {
                        if editor.selection.isEmpty {
                            DesignMenu(model: model, item: item)
                        } else {
                            CanvasLayerMenu(editor: editor)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("design-canvas")
                VStack(spacing: Space.s2) {
                    if editor.syncHalted || editor.syncStuck {
                        CoreNotice(
                            symbol: "exclamationmark.triangle",
                            title: editor.syncHalted ? DesignEditor.haltedSentence : DesignEditor.stuckSentence, tone: .warn
                        ) {
                            Button("Reopen") { editor.reopen() }.buttonStyle(.coreSecondary)
                                .help("Build the canvas again from the Core's copy. Edits that were not sent are lost.")
                        }
                        .frame(maxWidth: Space.s8 * 14)
                    } else if editor.assetFailures > 0 {
                        CoreNotice(
                            symbol: "photo.badge.exclamationmark",
                            title: editor.assetFailures == 1
                                ? "An image could not load." : "\(editor.assetFailures) images could not load.",
                            tone: .warn
                        ) {
                            Button("Try Again") { editor.retryAssets() }.buttonStyle(.corePlain)
                        }
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
                .animation(Motion.out(Motion.ui), value: editor.syncHalted)
                .animation(Motion.out(Motion.ui), value: model.composer == nil)
                .padding(Space.s4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coreWell(radius: Radius.pane)
            .onAppear { sync() }
            .onChange(of: model.readOnly) { sync() }
            .onChange(of: model.composer?.phase == .drawing) { editor.revealPaused = model.composer?.phase == .drawing }
            Island("Inspector") { InspectorIsland(editor: editor) }.frame(width: Space.s8 * 10)
        }
        .environment(model.collab)
        .onChange(of: model.assets, initial: true) { _, list in
            editor.libraryFonts = list.filter { $0.kind == .font && $0.check == .ok }
        }
        // A trigger: the app's own dialog shows the list (like every other Design dialog), then it resets.
        .onChange(of: editor.shortcutsOpen) { _, open in
            guard open else { return }
            editor.shortcutsOpen = false
            model.host.shell.present(
                ShellDialog(id: "design-shortcuts") { ShortcutsSheet { model.host.shell.closeDialog() } })
        }
    }

    /// What the model knows that the editor needs: a viewer cannot edit; the layers panel rests while the AI draws.
    private func sync() {
        editor.readOnly = model.readOnly
        editor.revealPaused = model.composer?.phase == .drawing
    }
}
