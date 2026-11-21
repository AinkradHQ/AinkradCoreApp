import Accounts
import CoreUI
import Shell
import SwiftUI

/// The setup that follows pairing (E3-1), over the live desktop: About you, an AI account, Look, the Mac runner and a last
/// page. One card; Back and Continue at the bottom; every page but Look and the last can be skipped.
struct SetupTourView: View {
    @Bindable var model: SetupTourModel
    let accounts: AccountsModel
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The AI page is adding an account (its own buttons show instead of setup's).
    @State private var addingAccount = false
    /// The page's own height, so the card hugs it.
    @State private var pageHeight: CGFloat = Space.s8 * 14

    var body: some View {
        if let step = model.step {
            ZStack {
                // Keeps the wallpaper behind from taking clicks while setup is open (the desktop is hidden until it ends).
                Color.clear.ignoresSafeArea().contentShape(Rectangle())
                VStack(alignment: .leading, spacing: Space.s4) {
                    // The approved setup header (02 Setup): the progress bars alone, centred, as on the welcome page.
                    SetupBars(at: step.bar).frame(maxWidth: .infinity)
                    ScrollView {
                        page(step).id(step).transition(.opacity.combined(with: .offset(x: coreMove(reduce, 12))))
                            .padding(.vertical, Space.s1)
                            .background {
                                GeometryReader { g in Color.clear.preference(key: PageHeight.self, value: g.size.height)
                                }
                            }
                    }
                    // Hugs a short page (no gap) and scrolls a tall one.
                    .scrollIndicators(.hidden)
                    .frame(height: min(max(pageHeight, 1), Space.s8 * 14))
                    .onPreferenceChange(PageHeight.self) { pageHeight = $0 }
                    footer(step)
                }
                .foregroundStyle(palette.text)
                .coreFont(size: MacTextSize.body)
                .padding(EdgeInsets(top: 28, leading: 36, bottom: 24, trailing: 36))  // the approved 02 Setup card
                // The Look page shows the pane's own look, so the sliders can be seen working on the card itself.
                .coreFrame(radius: Radius.pane, part: .panes)
                .frame(width: 780)
                .accessibilityElement(children: .contain)
            }
            .animation(reduce ? .easeOut(duration: 0.2) : Motion.out(Motion.ui), value: step)
            .onExitCommand { model.back() }
        }
    }

    @ViewBuilder private func page(_ step: SetupTourModel.Step) -> some View {
        switch step {
        case .ai:
            SetupPage(
                meta: "Step 3 of 6", title: model.accountCount() > 0 ? "Your AI accounts" : "Connect an AI account",
                sub: "Your Core can use as many as you like. It picks the right one for each job."
            ) {
                SetupAIStep(model: accounts, inFlow: $addingAccount)
            }
        case .look: SetupLookPage(shell: shell)
        case .runner:
            if let m = model.macRunner { SetupRunnerPage(macRunner: m) }
        case .ready: ready
        default: SetupYouPage(model: model, step: step)
        }
    }

    @ViewBuilder private func footer(_ step: SetupTourModel.Step) -> some View {
        // Adding an AI account has its own Back and Connect: one row of buttons at a time.
        if !(step == .ai && addingAccount) { buttons(step) }
    }

    private func buttons(_ step: SetupTourModel.Step) -> some View {
        HStack {
            if !model.isFirst { Button("Back") { model.back() }.coreGlassButton().coreShortcut(.cancel) }
            Spacer()
            if step.isYou || (step == .ai && model.accountCount() == 0) {
                Button("Skip") { model.next() }.coreGlassButton()
                    .keyboardShortcut("s", modifiers: .command).environment(\.coreKeycap, "⌘S")
            }
            Button(label(step)) { step == .ready ? model.finish() : model.next() }
                .buttonStyle(CoreButtonStyle(.prominent, size: .large)).coreShortcut(.primary)
        }
    }

    private func label(_ step: SetupTourModel.Step) -> String {
        switch step {
        case .life: model.detour == nil ? "Save about me" : "Done"
        case .look where model.detour != nil: "Done"
        case .ready: "Open Ainkrad"
        default: "Continue"
        }
    }

    private var ready: some View {
        SetupPage(
            meta: nil, title: "You are all set",
            sub: "Here is what we set up. You can change any of it later in Settings."
        ) {
            VStack(spacing: Space.s2) {
                row("person", "About you", model.aboutLine)
                row("sparkles", "AI accounts", model.aiLine)
                row("laptopcomputer", "This Mac", model.runnerLine)
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol, hue: GlassInk.slate, size: 28)
            Text(title).coreFont(size: MacTextSize.body, weight: .semibold)
            Spacer()
            Text(value).foregroundStyle(palette.text2)
        }
        .padding(Space.s3).coreWell()
        .accessibilityElement(children: .combine)
    }
}

/// Theme, transparency, blur, accent and wallpaper, changing the app behind the card as they are touched.
struct SetupLookPage: View {
    @Environment(\.coreAccent) private var paneAccent
    @Bindable var shell: ShellModel
    @Bindable private var look = LookPrefs.shared
    @Bindable private var accent = AccentPrefs.shared
    @Bindable private var wallpaper = WallpaperPrefs.shared
    @Environment(\.corePalette) private var palette

    var body: some View {
        SetupPage(meta: "Step 4 of 6", title: "Make it yours", sub: "Changes show right away, behind this window too.")
        {
            CoreSegmented(
                "Theme",
                segments: [
                    CoreSegment(ThemeChoice.night, "Night", symbol: "moon"),
                    CoreSegment(.day, "Day", symbol: "sun.max"),
                    CoreSegment(.sun, "Follow the sun"), CoreSegment(.system, "Follow the Mac"),
                ], selection: $shell.theme, fill: true)
            SetupGroup(title: "Transparency") {
                GlassSlider(value: transparency, in: 0...0.95, low: "Solid", high: "See-through")
            }
            SetupGroup(title: "Blur") { GlassSlider(value: $look.blur, in: 0...1, low: "Sharp", high: "Frosted") }
            SetupGroup(title: "Accent") {
                SetupFlow(spacing: Space.s3) {
                    ForEach(CoreAccent.allCases, id: \.self) { a in
                        Button {
                            accent.accent = a
                        } label: {
                            coreShape(Radius.chip).fill(a.fill).frame(width: 36, height: 26)
                                .overlay {
                                    if accent.accent == a {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(CoreQuietPressStyle())
                        .accessibilityLabel("\(a.title) accent")
                        .accessibilityAddTraits(accent.accent == a ? .isSelected : [])
                    }
                }
            }
            SetupGroup(title: "Wallpaper") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 6), spacing: Space.s2
                ) {
                    ForEach(CoreWallpaper.presets, id: \.self) { w in
                        Button {
                            wallpaper.choice = w
                        } label: {
                            VStack(spacing: Space.s1) {
                                WallpaperView(w, thumb: true).frame(height: 56).clipShape(coreShape(Radius.control))
                                    .overlay(alignment: .topTrailing) {
                                        if wallpaper.choice == w {
                                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white).frame(width: 16, height: 16)
                                                .background(GlassInk.accent(paneAccent), in: coreShape(Radius.chip / 2))
                                                .padding(4)
                                        }
                                    }
                                Text(w.title).coreFont(size: MacTextSize.meta)
                                    .foregroundStyle(wallpaper.choice == w ? palette.text : palette.text2)
                            }
                        }
                        .buttonStyle(CoreQuietPressStyle())
                        .accessibilityLabel("\(w.title) wallpaper")
                        .accessibilityAddTraits(wallpaper.choice == w ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// The slider reads left to right as more see-through; the Look stores how solid the surface is.
    private var transparency: Binding<Double> {
        Binding(get: { 1 - look.opacity }, set: { look.opacity = 1 - $0 })
    }
}

/// "Let this Mac help": the choice is only remembered here; the runner is added once the desktop is connected and this Mac
/// is unlocked with Touch ID (`MacRunnerModel.reconcile`).
struct SetupRunnerPage: View {
    let macRunner: MacRunnerModel
    @State private var on: Bool

    init(macRunner: MacRunnerModel) {
        self.macRunner = macRunner
        _on = State(initialValue: macRunner.useThisMac)
    }

    var body: some View {
        SetupPage(
            meta: "Step 5 of 6", title: "Let this Mac help",
            sub: "A runner does tasks for your Core, like builds and AI sessions, while this Mac is on."
        ) {
            GlassToggleTile(
                "Use this Mac as a runner",
                sub: on
                    ? "Asks for Touch ID once. \(MacRunnerModel.terminalsWarning)" : "Turn it on any time in Settings.",
                symbol: "laptopcomputer", isOn: $on, fill: true
            )
            .onChange(of: on) { _, v in macRunner.setPreference(v) }
            .accessibilityIdentifier("setup-mac-runner-switch")
            // TODO(E12-6): the "Send anonymous crash reports" switch of the approved mockup goes here once E12-6 builds the
            // crash-report service. It is left out until then, not hidden: there is nothing for it to turn on yet.
        }
    }
}

private struct PageHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
