import CoreUI
import SwiftUI

/// The Connections pane (CN1, CN6): page tiles and the Connect action in the header, the page, status chips at the foot.
struct ConnectionsView: View {
    @Environment(\.coreAccent) private var paneAccent
    let model: ConnectionsModel
    @FocusState private var paneFocus: Bool

    private func arrow(_ step: Int) -> KeyPress.Result {
        withAnimation(.smooth(duration: 0.2)) { model.move(step) }
        return .handled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                AppFilterTile(title: "Connections", count: model.shown.count, on: true, key: "") {}
            } actions: {
                AppActionTile(
                    title: "Connect", symbol: "plus", key: "⌘N", hue: GlassInk.accent(paneAccent), prominent: true
                ) {
                    model.beginAdd()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.service == nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    AccNotice(notice: model.host.elevationNotice)
                    if model.sample {
                        CoreNotice(
                            symbol: "info.circle", title: "Sample connections",
                            text:
                                "This page shows made-up connections to try things on. Nothing here reaches your Core."
                        )
                    }
                    content
                }
                .coreFont(size: MacTextSize.body)
                .foregroundStyle(GlassInk.primary)
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .focusable()
            .focused($paneFocus)
            .focusEffectDisabled()
            .onAppear { paneFocus = true }
            .retakeFocus(after: model.host.shell, pane: "connections") { paneFocus = true }
            .onKeyPress(.downArrow) { arrow(1) }
            .coreSideKeys { arrow($0) }
            .onKeyPress(.upArrow) { arrow(-1) }
            .onKeyPress(.return) { model.key("⏎") ? .handled : .ignored }
            .onKeyPress(.delete) { model.key("⌫") ? .handled : .ignored }
            .onKeyPress(.escape) {
                guard model.cursor != nil else { return .ignored }
                model.cursor = nil
                return .handled
            }
            .onKeyPress(characters: .letters) { model.key($0.characters.lowercased()) ? .handled : .ignored }
        }
        .paneLook(AppLookPrefs.shared("connections").look)
        .appLookTheme(AppLookPrefs.shared("connections"))
        .clipShape(coreShape(Radius.cardMac))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connections-pane")
    }

    @ViewBuilder private var content: some View {
        if model.service == nil {
            AccStateCard(
                symbol: "link", title: "Not connected to a Core",
                text: "Connect this Mac to your Core first. Then you sign in to GitHub, Jira and others here.")
        } else {
            switch model.load {
            case .loading: AccSkeleton()
            case .ready:
                ConnListPage(model: model).transition(.opacity)
            default:
                AccStateCard(
                    symbol: "exclamationmark.triangle", title: "Couldn't load connections",
                    text: "Your Core didn't answer. Nothing was changed.", tone: .fail
                ) {
                    AppActionTile(
                        title: "Try again", symbol: "arrow.clockwise", key: "R", hue: GlassInk.accent(paneAccent)
                    ) {
                        Task { await model.reload() }
                    }
                }
            }
        }
    }
}
