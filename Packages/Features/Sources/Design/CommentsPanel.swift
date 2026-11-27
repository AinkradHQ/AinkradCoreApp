import CoreUI
import SwiftUI

extension DesignEditor {
    /// The screens: frames and components right under a page, in page order.
    var screens: [DesignLayer] {
        layers.children(of: nil).flatMap { p in
            layers.children(of: p.id).filter { $0.type == "frame" || $0.type == "component" }
        }
    }
}

/// The header's comment and AI controls of an open design: a Comments tile with the open count and a menu for the AI
/// (pause, take over, resume) in plain words.
struct DesignCollabHeader: View {
    let model: DesignModel
    let doc: DesignDoc
    let editor: DesignEditor?
    @State private var comments = false
    @State private var aiOpen = false
    @Environment(\.coreAccent) private var paneAccent

    var body: some View {
        Group {
            if let editor, doc.kind == .design {
                let n = model.collab.openCount(doc.id)
                AppActionTile(
                    title: n > 0 ? "Comments \(n)" : "Comments", symbol: "bubble.left", key: "",
                    hue: GlassInk.accent(paneAccent)
                ) { comments.toggle() }
                .help("Notes on the screens of this design")
                .accessibilityIdentifier("design-comments")
                .popover(isPresented: $comments, arrowEdge: .bottom) {
                    CommentsPanel(model: model, doc: doc, editor: editor)
                }
            }
            if doc.kind != .mockup { aiMenu }
        }
        #if DEBUG
        .onAppear { if model.debugCommentsOpen { comments = true } }
        .onChange(of: model.debugCommentsOpen) { _, on in comments = on }
        #endif
    }

    private var aiMenu: some View {
        CoreDropdown(items: AIControl.items(doc: doc, model: model), isPresented: $aiOpen) {
            Label(doc.aiPaused ? "AI paused" : "AI", systemImage: doc.aiPaused ? "pause.circle" : "sparkles")
        }
        .disabled(model.readOnly)
        .task(id: doc.id) { await model.collab.load(doc.id) }
        .help(
            doc.aiPaused
                ? "AI cannot change this design until you resume it" : "Pause AI or take over this design"
        )
        .accessibilityIdentifier("design-ai-control")
    }
}

/// What the AI menu offers, in words a person understands.
enum AIControl {
    @MainActor static func items(doc: DesignDoc, model: DesignModel) -> [CoreDropdownItem] {
        if doc.aiPaused {
            return [
                CoreDropdownItem(
                    "Resume AI", symbol: "play.circle", note: "AI may draw here again"
                ) { Task { await model.setAI(doc, .resume) } }
            ]
        }
        return [
            CoreDropdownItem("Pause AI", symbol: "pause.circle", note: "AI stops writing until you resume") {
                Task { await model.setAI(doc, .pause) }
            },
            CoreDropdownItem("Take over", symbol: "hand.raised", note: "You edit, AI waits") {
                Task { await model.setAI(doc, .takeOver) }
            },
        ]
    }
}

/// The comments of a design: Open and Resolved, a thread per note, and a field to add one on a screen.
struct CommentsPanel: View {
    let model: DesignModel
    let doc: DesignDoc
    let editor: DesignEditor
    @State private var show = Show.open
    @State private var text = ""
    @State private var screen = ""
    @State private var pin = true
    @State private var replyTo: DesignComment?
    @State private var busy = false

    enum Show: Hashable { case open, resolved }

    private var collab: DesignCollab { model.collab }
    private var all: [DesignComment] { collab.comments[doc.id] ?? [] }
    private var shown: [DesignComment] { all.filter { $0.resolved == (show == .resolved) } }
    private var screens: [DesignLayer] { editor.screens }
    /// The layer to pin to: the selected one, when it is not itself a screen.
    private var pinned: String? {
        guard let s = editor.selection.first, let l = editor.layers[s], !screens.contains(where: { $0.id == s }),
            l.type != "page"
        else { return nil }
        return s
    }
    private var target: String {
        screens.contains { $0.id == screen } ? screen : (editor.targetFrame()?.id ?? screens.first?.id ?? "")
    }
    private var draft: NewDesignComment {
        NewDesignComment(
            screen: replyTo?.screen ?? target, body: text, node: replyTo == nil && pin ? pinned : nil,
            parent: replyTo?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreSegmented(
                "Show",
                segments: [
                    CoreSegment(Show.open, "Open \(all.filter { !$0.resolved }.count)"),
                    CoreSegment(Show.resolved, "Resolved \(all.filter(\.resolved).count)"),
                ], selection: $show)
            if shown.isEmpty {
                Text(show == .open ? "No open comments. Add one below." : "Nothing resolved yet.")
                    .foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity, minHeight: Space.s8 * 2)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(DesignCollab.threads(shown), id: \.root.id) { t in
                            thread(t.root, t.replies)
                        }
                    }
                }
                .scrollIndicators(.never).frame(maxHeight: Space.s8 * 8)
            }
            composer
        }
        .padding(Space.s4).frame(width: Space.s8 * 14)
        .accessibilityIdentifier("design-comments-panel")
    }

    private func name(_ l: DesignLayer?) -> String { l?.title ?? "A removed screen" }

    private func thread(_ c: DesignComment, _ replies: [DesignComment]) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            note(c)
            ForEach(replies) { r in note(r).padding(.leading, Space.s4) }
            HStack(spacing: Space.s2) {
                Button("Reply") { replyTo = c }.buttonStyle(CoreButtonStyle(.plain, size: .small))
                Button(c.resolved ? "Reopen" : "Resolve") {
                    Task { await collab.resolve(doc: doc.id, id: c.id, !c.resolved) }
                }
                .buttonStyle(CoreButtonStyle(.plain, size: .small)).disabled(model.readOnly)
            }
        }
        .padding(Space.s2).background(GlassInk.well, in: coreShape(Radius.control))
    }

    private func note(_ c: DesignComment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Space.s2) {
                Text(AboutIsland.who(c.author)).coreFont(size: MacTextSize.meta, weight: .semibold)
                Button {
                    focus(c)
                } label: {
                    Label(name(editor.layers[c.screen]), systemImage: c.node == nil ? "rectangle.dashed" : "mappin")
                        .coreFont(size: MacTextSize.meta)
                }
                .buttonStyle(.plain).foregroundStyle(GlassInk.secondary)
                .help("Show it on the canvas")
                Spacer(minLength: 0)
                Text(Ago.words(c.createdAt)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Text(c.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    /// Selects what the note is on and brings it into view.
    private func focus(_ c: DesignComment) {
        let id = c.node.flatMap { editor.layers[$0] != nil ? $0 : nil } ?? c.screen
        if editor.select(id) { editor.fitSelection() }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let r = replyTo {
                HStack {
                    Label("Replying to \(AboutIsland.who(r.author))", systemImage: "arrowshape.turn.up.left")
                        .foregroundStyle(GlassInk.secondary)
                    Spacer()
                    CoreIconButton(symbol: "xmark", label: "Cancel the reply") { replyTo = nil }
                }
            } else if screens.count > 1 {
                CoreSelect(
                    "On screen", selection: Binding(get: { target }, set: { screen = $0 }),
                    options: screens.map { CoreSelectOption($0.id, $0.title) })
            } else if screens.isEmpty {
                Text("Add a frame first: a comment belongs to a screen.").foregroundStyle(GlassInk.secondary)
            }
            CoreTextField(
                "Comment", placeholder: "What should change?", text: $text,
                error: text.count > NewDesignComment.limit ? "At most 4000 characters." : nil
            ) { post() }
            if replyTo == nil, let p = pinned {
                Toggle("Pin to \(editor.layers[p]?.title ?? "the selected layer")", isOn: $pin)
                    .toggleStyle(.checkbox)
            }
            if let e = collab.error { CoreFieldError(e) }
            HStack {
                Spacer()
                Button("Post") { post() }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: busy))
                    .disabled(!draft.valid || draft.screen.isEmpty || busy || model.readOnly)
                    .help(model.readOnly ? "This device can look at designs but not change them." : "Post the comment")
            }
        }
    }

    private func post() {
        guard draft.valid, !draft.screen.isEmpty, !busy else { return }
        busy = true
        Task {
            if await collab.post(doc: doc.id, draft) {
                text = ""
                replyTo = nil
                show = .open
            }
            busy = false
        }
    }
}
