import CoreUI
import SwiftUI

/// The toolbar items of an open design (V3-04), for the top bar's actions: Undo, Redo, Zoom to Selection, Versions, About.
/// Every one shows its words and shortcut on hover; Undo, Redo and the zoom are also keys on the canvas (⌘Z, ⇧⌘Z, ⌘1).
struct EditorToolbar: View {
    let editor: DesignEditor
    @Binding var aboutOpen: Bool

    var body: some View {
        HStack(spacing: Space.s1) {
            CoreIconButton(symbol: "arrow.uturn.backward", label: "Undo the last change (⌘Z)") { editor.undo() }
            CoreIconButton(symbol: "arrow.uturn.forward", label: "Redo the change you undid (⇧⌘Z)") { editor.redo() }
            CoreIconButton(symbol: "scope", label: "Zoom to the selection (⌘1)") { editor.fitSelection() }
            CoreIconButton(
                symbol: "clock.arrow.circlepath", label: "Show this design's versions and go back to one",
                selected: editor.versionsOpen
            ) { editor.versionsOpen = true }
            CoreIconButton(
                symbol: "info.circle", label: "Show what this design is and where it is used", selected: aboutOpen
            ) {
                aboutOpen.toggle()
            }
        }
        .disabled(!editor.attached)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor tools")
    }
}

/// Who else is on the design right now (T3 awareness): other devices and AI sessions, with what each has selected. Presence
/// is never stored, so an empty strip simply means you are alone.
struct PresenceStrip: View {
    let peers: [DesignPeer]

    var body: some View {
        HStack(spacing: Space.s1) {
            if peers.isEmpty {
                Text("Only you").foregroundStyle(GlassInk.secondary)
            } else {
                ForEach(peers.prefix(4)) { p in
                    HStack(spacing: Space.s1) {
                        Image(systemName: p.isAI ? "sparkles" : "person").accessibilityHidden(true)
                        Text(p.label).lineLimit(1)
                    }
                    .coreFont(size: MacTextSize.meta, weight: .medium)
                    .padding(.horizontal, Space.s2)
                    .frame(height: MacSize.chip)
                    .background(GlassInk.well, in: coreShape(Radius.chip))
                    .help(Self.words(p))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.words(p))
                }
                if peers.count > 4 { Text("+\(peers.count - 4)").foregroundStyle(GlassInk.secondary) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("People on this design")
    }

    static func words(_ p: DesignPeer) -> String {
        let who = p.isAI ? "\(p.label), an AI session" : p.label
        return p.selection.isEmpty
            ? "\(who), looking around" : "\(who), has \(Words.count(p.selection.count, "layer")) selected"
    }
}

/// The Ask… field (V3-04): a line to the AI about this design, sent with the ids of what is selected; it draws on this
/// canvas. It sits at the right end of the canvas toolbar.
struct AskField: View {
    @Bindable var editor: DesignEditor
    @FocusState private var focused: Bool

    var body: some View {
        // TODO(design-system): proposal CoreInputBar (a floating glass line with a field and a send button); Design and the
        // Brain's Ask both want one.
        HStack(spacing: Space.s2) {
            Image(systemName: "sparkles").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            TextField("", text: $editor.askText)
                .textFieldStyle(.plain)
                .coreFont(size: MacTextSize.body)
                .focused($focused)
                .disabled(!editor.canAsk)
                .onSubmit { Task { await editor.submitAsk() } }
                .overlay(alignment: .leading) {
                    if editor.askText.isEmpty {
                        Text(placeholder).foregroundStyle(GlassInk.secondary).lineLimit(1).allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Ask the AI about this design")
            CoreIconButton(symbol: "arrow.up", label: "Send to the AI (Return)") { Task { await editor.submitAsk() } }
                .disabled(!editor.canAsk || editor.askText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Space.s3)
        .frame(
            minWidth: Space.s8 * 4, maxWidth: Space.s8 * 11, minHeight: MacSize.controlLg + Space.s1,
            maxHeight: MacSize.controlLg + Space.s1
        )
        .background(GlassInk.well, in: coreShape(Radius.control))
        .help(
            editor.canAsk
                ? "Ask the AI to change or explain this design"
                : "Asking the AI arrives with AI drawing, in a later update")
    }

    private var placeholder: String {
        guard editor.canAsk else { return "Ask… is not available yet" }
        switch editor.selection.count {
        case 0: return "Ask AI about this design…"
        case 1: return "Ask AI about the selected layer…"
        default: return "Ask AI about the \(editor.selection.count) selected layers…"
        }
    }
}

/// Versions: what the Core kept (auto, named, approved), a name to keep the current state, and Restore. Restoring is one
/// ordinary edit for everyone on the design, so Undo brings the later state back.
struct VersionsSheet: View {
    @Bindable var editor: DesignEditor
    @State private var name = ""

    var body: some View {
        CoreSheet("Versions") {
            VStack(alignment: .leading, spacing: Space.s3) {
                CoreTextField("Keep the current state as", placeholder: "Name this version", text: $name) { save() }
                if let note = editor.versionsNote {
                    Text(note).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(spacing: Space.s1) {
                        ForEach(editor.versions) { v in
                            CoreRow(
                                v.name.isEmpty ? Self.kind(v.kind) : v.name, subtitle: Self.line(v),
                                symbol: Self.symbol(v.kind)
                            ) {
                                Button("Restore") { Task { await editor.restore(v) } }
                                    .buttonStyle(.coreSecondary)
                                    .disabled(editor.versionsBusy)
                                    .help("Go back to this version. Undo brings the later state back.")
                            }
                        }
                    }
                }
                .frame(maxHeight: Space.s8 * 8)
            }
        } footer: {
            Button("Done") { editor.versionsOpen = false }.buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
            Button("Save Version") { save() }.buttonStyle(.coreProminent)
                .disabled(editor.versionsBusy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .task { await editor.loadVersions() }
        .accessibilityIdentifier("design-versions")
    }

    private func save() {
        let n = name
        name = ""
        Task { await editor.saveVersion(named: n) }
    }

    static func kind(_ k: DesignVersion.Kind) -> String {
        switch k {
        case .auto: "Automatic"
        case .named: "Named"
        case .approval: "Approved"
        }
    }
    static func symbol(_ k: DesignVersion.Kind) -> String {
        switch k {
        case .auto: "clock"
        case .named: "tag"
        case .approval: "checkmark.seal"
        }
    }
    static func line(_ v: DesignVersion) -> String {
        [kind(v.kind), Ago.words(v.createdAt), AboutIsland.who(v.createdBy)].filter { !$0.isEmpty }.joined(
            separator: " · ")
    }
}
