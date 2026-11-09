import CoreUI
import Shell
import SwiftUI

/// The window content: first run before the desktop, the desktop once paired, a stop when the connection cannot go on.
public struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme

    public init(app: AppModel) { self.app = app }

    public var body: some View {
        Group {
            switch app.phase {
            case .starting: sky.overlay { CoreBusyBar().frame(width: Space.s8 * 4) }
            case .firstRun: FirstRunView(model: app.firstRun)
            case .desktop: ShellView(shell: app.shell)
            case .blocked(let f): blocked(f)
            }
        }
        .task { await app.start() }
        .coreTheme()
        .coreConfirm(
            "Forget this Core?", isPresented: $app.confirmForget,
            message: "This Mac's keys for it are deleted. You will need a new pairing code to connect again.",
            confirmTitle: "Forget Core", destructive: true
        ) { Task { await app.forgetCore() } }
    }

    private var sky: some View {
        Color.clear.overlay {
            Image(scheme == .dark ? "HomeSky" : "HomeSkyDay", bundle: .main).resizable().scaledToFill()
        }
        .clipped().ignoresSafeArea().accessibilityHidden(true)
    }

    private func blocked(_ f: Failure) -> some View { BlockedView(app: app, failure: f) }
}

private struct BlockedView: View {
    let app: AppModel
    let failure: Failure
    @Environment(\.colorScheme) private var scheme
    @Environment(\.corePalette) private var palette

    var body: some View {
        // The card is centred in the whole window and the sky sits behind it, so the picture can never move the card.
        FailureView(
            failure: failure, retryAt: nil,
            actions: failure.fatal && failure.kind != .identityMismatch
                ? [FailureAction(label: "Connect again", style: .primary) { Task { await app.forgetCore() } }]
                : [
                    FailureAction(label: "Forget this Core…") { app.confirmForget = true },
                    FailureAction(label: "Try again", style: .primary) { Task { await app.tryAgain() } },
                ]
        )
        .foregroundStyle(palette.text)
        .font(.system(size: MacTextSize.body))
        .padding(Space.s6)
        .coreFrame(radius: Radius.panel, part: .dialogs)
        .frame(width: Space.s8 * 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            Image(scheme == .dark ? "HomeSky" : "HomeSkyDay", bundle: .main).resizable().scaledToFill()
                .clipped().accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}
