import CoreUI
import SwiftUI

/// The quick New AI session (ai-sessions-2026-11-12, new-quick): the session is already open and waiting, so the page shows
/// what it runs with, Advanced… for the rest, and recent projects to start in instead. The composer below takes the first
/// message, like typing `claude` in a terminal.
struct NewSessionHero: View {
    @Bindable var model: AgentsModel
    let session: AgentSessionInfo
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    var body: some View {
        let places = ConversationWords.recentPlaces(model.sessions.items)
        VStack(spacing: Space.s3) {
            Image(systemName: "bubble.left").coreFont(size: MacTextSize.large, weight: .semibold)
                .foregroundStyle(palette.btnInk)
                .frame(width: Space.s8 + Space.s5, height: Space.s8 + Space.s5)
                .background(palette.btnPrimary, in: coreShape(Radius.cardMac))
                .accessibilityHidden(true)
            Text("New AI session").coreFont(size: MacTextSize.large, weight: .semibold).accessibilityAddTraits(
                .isHeader)
            Text("It is open and waiting. Type your first message, like typing `claude` in a terminal.")
                .foregroundStyle(palette.text2).multilineTextAlignment(.center).frame(maxWidth: Space.s8 * 15)
                .fixedSize(horizontal: false, vertical: true)
            // What it runs with. The session already exists, so these are facts; Advanced… opens a new one with others.
            HStack(spacing: Space.s2) {
                CoreChip(AgentWords.toolName(session.harness), symbol: AgentsModel.harnessSymbol(session.harness))
                CoreChip(model.runnerName(session.runner))
                CoreChip(session.project ?? "Fresh folder", symbol: "folder")
                CoreChip(session.model ?? "Default model")
                Button("Advanced…") { model.openNewSession(advanced: true) }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .help("Choose the tool, runner, folder or repo, model and account order")
            }
            if !places.isEmpty {
                Text("Or start in a project").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .padding(.top, Space.s3)
                HStack(spacing: Space.s3) {
                    ForEach(places) { p in
                        CoreRow(
                            p.project,
                            subtitle: [p.branch, model.runnerName(p.runner)].compactMap { $0 }
                                .joined(separator: " · "),
                            symbol: "folder"
                        ) { model.openNewSession(advanced: true, runner: p.runner, place: p) }
                        .fixedSize()
                        .coreWell(radius: Radius.row)
                        .help("Start a new AI session in \(p.project)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(palette.text)
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduce ? 0 : Space.s2)
        .onAppear { withAnimation(Motion.out(Motion.ui)) { shown = true } }
    }
}
