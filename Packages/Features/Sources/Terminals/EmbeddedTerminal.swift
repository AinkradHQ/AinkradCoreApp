import CoreUI
import Shell
import SwiftUI

/// A real terminal inside another screen (the AI session's Terminal tab): a shell in the session's folder on its runner, drawn
/// by the same emulator the Terminals app uses. It opens when the view first appears and stays for the life of the view.
public struct EmbeddedTerminal: View {
    let model: TerminalsModel
    let runner: String
    let session: String
    @State private var terminal: TerminalSession?
    @State private var failure: String?
    @State private var opening = false
    @Environment(\.corePalette) private var palette

    public init(model: TerminalsModel, runner: String, session: String) {
        self.model = model
        self.runner = runner
        self.session = session
    }

    public var body: some View {
        Group {
            if let terminal {
                TerminalPaneView(model: model, session: terminal)
            } else if let failure {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(failure).coreFont(size: MacTextSize.body).foregroundStyle(palette.text2)
                    Button("Try again") { Task { await open() } }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Opening a terminal in the session's folder…").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(palette.text2).padding(Space.s3)
            }
        }
        .clipShape(coreShape(Radius.row))
        .task(id: session) { if terminal == nil { await open() } }
    }

    private func open() async {
        guard !opening else { return }
        opening = true
        defer { opening = false }
        failure = nil
        terminal = await model.embed(on: runner, session: session)
        if terminal == nil { failure = model.embedError ?? "The terminal did not open." }
    }
}

/// A terminal the Core already opened, inside another screen (Leyline's host view): attached when the view first appears.
public struct AttachedTerminal: View {
    let model: TerminalsModel
    let terminal: String
    @State private var session: TerminalSession?
    @State private var missing = false
    @Environment(\.corePalette) private var palette

    public init(model: TerminalsModel, terminal: String) {
        self.model = model
        self.terminal = terminal
    }

    public var body: some View {
        Group {
            if let session {
                TerminalPaneView(model: model, session: session)
            } else {
                Text(missing ? "That terminal has ended." : "Connecting…").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(palette.text2).padding(Space.s3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task(id: terminal) {
            session = await model.embed(existing: terminal)
            missing = session == nil
        }
    }
}
