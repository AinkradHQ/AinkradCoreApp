import CoreUI
import SwiftUI

/// The one card under the map: what is going on now, in the mockup's words. Ready (Update everything), updating (four
/// steps with their bars and seconds), runners following, done, went back (with the plain reason and a countdown), one
/// runner updating, this app's own update, and up to date.
struct UpdatesHeroCard: View {
    let shell: ShellModel
    let t: Date
    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette

    private var model: UpdatesModel { shell.updates }

    var body: some View {
        let hero = model.hero
        VStack(alignment: .leading, spacing: Space.s4 + 2) {
            switch hero {
            case .available: available
            case .updating: updating
            case .following: following
            case .done: done
            case .wentBack: wentBack
            case .runner: runner
            case .macApp: macApp
            case .upToDate: upToDate
            }
        }
        .updSwap(hero)
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint(hero), in: coreShape(Radius.cardMac))
        .coreWell()
        .animation(Motion.out(Motion.move), value: hero)
        .accessibilityElement(children: .contain)
    }

    private func tint(_ hero: UpdatesHero) -> Color {
        switch hero {
        case .available, .updating, .runner: GlassInk.accent(accent).opacity(0.16)
        case .following, .done: palette.success.opacity(0.09)
        case .wentBack: palette.error.opacity(0.09)
        case .macApp, .upToDate: .clear
        }
    }

    // MARK: the states

    private var available: some View {
        let to = model.target ?? ""
        let names = model.otherRunners.filter(\.online).map(\.name)
        return Group {
            top(symbol: "arrow.down.to.line", lit: true, title: "Core \(to) is ready", sub: nightSub) {
                everythingButton("Update everything")
            }
            HStack(spacing: Space.s2) {
                UpdFact(symbol: "server.rack", text: "Core and its runner first · about 25 s")
                if !names.isEmpty {
                    UpdFact(symbol: "cpu", text: "Then \(Self.list(names)), one at a time")
                }
                UpdFact(symbol: "checkmark.shield", text: "Snapshot first · goes back by itself if anything fails")
            }
        }
    }

    private var updating: some View {
        let run = model.run ?? CoreRun(from: "", to: "", at: t)
        let gap = run.gapSeconds(at: t)
        return Group {
            top(
                symbol: "arrow.down.to.line", lit: true, title: "Updating Core to \(run.to)",
                sub: "You can keep working. Core restarts once, for a few seconds."
            ) { lockedButton }
            HStack(alignment: .top, spacing: Space.s2) {
                ForEach(CoreRun.Step.allCases, id: \.self) { s in
                    step(
                        s, fill: run.fill(s, at: t), state: s.rawValue < run.step.rawValue ? 1 : s == run.step ? 0 : -1,
                        seconds: run.took[s], waiting: s == .restart && gap != nil)
                }
            }
            HStack(spacing: Space.s3) {
                message(run, gap: gap).updSwap("\(run.step.rawValue)-\(gap == nil)-\(run.backAt == nil)")
                Spacer(minLength: Space.s2)
                Text(gap.map { "Waiting for the Core · \($0) s" } ?? "About \(run.secondsLeft(at: t)) s left")
                    .foregroundStyle(GlassInk.secondary).monospacedDigit()
            }
            .coreFont(size: MacTextSize.body)
        }
    }

    private func message(_ run: CoreRun, gap: Int?) -> Text {
        let (lead, rest): (String, String) =
            switch run.step {
            case .snapshot: ("Taking a snapshot.", "A safe copy of your data, just in case.")
            case .install: ("Installing \(run.to).", "Your work keeps running.")
            case .restart:
                gap != nil
                    ? ("Core is restarting.", "The connection drops for a few seconds. This is expected.")
                    : run.backAt != nil
                        ? ("Connected again.", "Core \(run.to) is up.") : ("Starting Core \(run.to).", "")
            case .health: ("Making sure everything works.", "AI Sessions, runners and storage.")
            }
        return Text(lead).fontWeight(.semibold).foregroundColor(GlassInk.primary)
            + Text(rest.isEmpty ? "" : " \(rest)").foregroundColor(GlassInk.secondary)
    }

    private var following: some View {
        let names = model.otherRunners.filter { model.queue.contains($0.id) }.map(\.name)
        return top(
            check: true, title: "Core is on \(model.coreVersion ?? ""). Now the runners.",
            sub: names.isEmpty
                ? "Checking which runners need it."
                : "\(Self.list(names)) update one at a time, so the others keep working."
        ) { lockedButton }
    }

    private var done: some View {
        let f = model.finished ?? UpdatesFinished(version: "", runners: 0, seconds: 0)
        let who = f.runners == 0 ? "Core" : f.runners == 1 ? "Core and its runner" : "Core and all \(f.runners) runners"
        return top(
            check: true, title: "Everything is on \(f.version)",
            sub: "\(who). Took \(f.seconds) s. A snapshot was kept, just in case."
        ) {
            Button("What is new") { shell.coreUpdateNews?() }.buttonStyle(CoreButtonStyle(.secondary))
                .keyboardShortcut("i").environment(\.coreKeycap, "⌘I")
                .disabled(shell.coreUpdateNews == nil)
        }
    }

    private var wentBack: some View {
        let s = model.core
        let to = s.to ?? model.target ?? "The new version"
        let failed = Self.failedStep(s.error)
        let why =
            failed == .health
            ? "\(to) did not pass its health check: \(s.errorWords)" : "\(to) did not go in: \(s.errorWords)"
        let wait = model.waitLeft(at: t)
        return Group {
            top(
                symbol: "exclamationmark.triangle", tone: palette.error,
                title: "The update did not work, so Core went back to \(model.coreVersion ?? s.current)",
                sub: "\(why) Everything was restored from the snapshot. All your data is safe."
            ) { EmptyView() }
            HStack(alignment: .top, spacing: Space.s2) {
                ForEach(CoreRun.Step.allCases, id: \.self) { st in
                    step(
                        st, fill: st.rawValue <= failed.rawValue ? 1 : 0,
                        state: st.rawValue < failed.rawValue ? 1 : st == failed ? 2 : -1, seconds: nil, waiting: false)
                }
            }
            HStack(spacing: Space.s3) {
                Text(
                    wait != nil
                        ? "Core needs a few minutes before the next try. We will also try again tonight."
                        : "You can try again now. It also tries again by itself tonight."
                )
                .foregroundStyle(GlassInk.secondary)
                Spacer(minLength: Space.s2)
                Button("See what happened") { shell.showWhatHappened() }.buttonStyle(CoreButtonStyle(.secondary))
                    .keyboardShortcut("l").environment(\.coreKeycap, "⌘L")
                everythingButton("Try again")
            }
            .coreFont(size: MacTextSize.body)
        }
    }

    private var runner: some View {
        let r = model.otherRunners.first { [.asked, .updating].contains(model.state($0)) }
        return top(
            symbol: "cpu", lit: true,
            title: "\(r?.name ?? "A runner") is updating to \(model.check?.latestRunner ?? model.coreVersion ?? "")",
            sub: "Core and the other runners are up to date and keep working."
        ) { EmptyView() }
    }

    private var macApp: some View {
        let ready = model.appReady
        return top(
            symbol: "laptopcomputer", lit: true,
            title: ready.map { "Ainkrad \($0) is ready to install" }
                ?? "Ainkrad \(model.appDownloading ?? "") is downloading",
            sub: ready != nil
                ? "The app restarts in a few seconds. Your AI Sessions keep running on the Core."
                : "Core and runners are up to date. This app updates on its own, below."
        ) {
            if ready != nil {
                Button("Later") { shell.showToast("It installs when you quit Ainkrad.", kind: .info) }
                    .buttonStyle(CoreButtonStyle(.plain))
                    .keyboardShortcut("r", modifiers: [.command, .option]).environment(\.coreKeycap, "⌥⌘R")
                Button("Restart to install") { model.installApp?() }.buttonStyle(CoreButtonStyle(.prominent))
                    .keyboardShortcut("r", modifiers: [.command, .shift]).environment(\.coreKeycap, "⌘⇧R")
                    .disabled(model.installApp == nil)
            }
        }
    }

    private var upToDate: some View {
        let behindRunner = model.otherRunners.contains { model.state($0) != .upToDate && model.state($0) != .offline }
        let appBehind = model.appReady != nil || model.appDownloading != nil
        let all = !behindRunner && !appBehind
        let n = model.listed.count
        return top(
            symbol: "checkmark", tone: palette.success, title: all ? "Everything is up to date" : "Core is up to date",
            sub: all
                ? "Core \(model.coreVersion ?? ""), \(n == 1 ? "1 runner" : "\(n) runners") and this app."
                : appBehind ? "This app has an update of its own, below." : "A runner is catching up, below."
        ) { EmptyView() }
    }

    // MARK: parts

    /// Update everything or Try again: locks the moment it is pressed (the model ignores a second press), and while the
    /// Core asked for a pause it counts down instead (never "Too many requests").
    @ViewBuilder private func everythingButton(_ title: String) -> some View {
        if let left = model.waitLeft(at: t) {
            Button("Try again in \(left / 60):\(String(format: "%02d", left % 60))") {}
                .buttonStyle(CoreButtonStyle(.prominent)).disabled(true).monospacedDigit()
        } else if model.pressed {
            lockedButton
        } else {
            Button(title) { Task { await model.updateEverything() } }.buttonStyle(CoreButtonStyle(.prominent))
                .keyboardShortcut("u").environment(\.coreKeycap, "⌘U")
                .disabled(!model.canUpdateEverything)
        }
    }

    private var lockedButton: some View {
        Button("Updating…") {}.buttonStyle(CoreButtonStyle(.prominent)).disabled(true)
    }

    /// One step: its bar, then its icon (a check once done, a cross where it failed), its name and the seconds it took.
    /// `state`: -1 waiting, 0 now, 1 done, 2 failed.
    private func step(_ s: CoreRun.Step, fill: Double, state: Int, seconds: TimeInterval?, waiting: Bool) -> some View {
        let symbol =
            state == 1
            ? "checkmark"
            : state == 2
                ? "xmark" : ["camera.viewfinder", "arrow.down.to.line", "power", "waveform.path.ecg"][s.rawValue]
        let ink: Color =
            state == 1
            ? palette.success : state == 2 ? palette.error : state == 0 ? GlassInk.primary : GlassInk.secondary
        return VStack(alignment: .leading, spacing: Space.s2) {
            UpdBar(value: fill, look: state == 2 ? .fail : state == 1 ? .done : .accent, waiting: waiting)
            HStack(spacing: Space.s1 + 2) {
                Image(systemName: symbol).coreFont(size: MacTextSize.meta + 1, weight: .semibold).foregroundStyle(ink)
                    .modifier(StepBreath(on: state == 0))
                    .contentTransition(.symbolEffect(.replace))
                Text(s.name).foregroundStyle(
                    state == 0 ? GlassInk.primary : state == 2 ? palette.error : GlassInk.secondary)
                Spacer(minLength: 0)
                if let seconds, state == 1 {
                    Text("\(max(1, Int(seconds.rounded()))) s").foregroundStyle(GlassInk.secondary).monospacedDigit()
                        .transition(.opacity)
                }
            }
            .coreFont(size: MacTextSize.meta + 1, weight: .medium)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(s.name), \(state == 1 ? "done" : state == 2 ? "failed" : state == 0 ? "now" : "next")")
    }

    private func top<Actions: View>(
        symbol: String = "", lit: Bool = false, tone: Color? = nil, check: Bool = false, title: String, sub: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: Space.s4) {
            UpdTile(size: 48, tint: check ? palette.success : tone ?? (lit ? GlassInk.accent(accent) : nil)) {
                if check {
                    UpdDrawnCheck().foregroundStyle(palette.success)
                } else {
                    Image(systemName: symbol).coreFont(size: 22, weight: .medium)
                        .foregroundStyle(tone ?? (lit ? GlassInk.accentInk(accent) : GlassInk.secondary))
                }
            }
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).coreFont(size: MacTextSize.title + 2, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(sub).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s2) { actions() }
        }
    }

    private var nightSub: String {
        let p = shell.corePage.prefs
        guard p.autoUpdate else { return "Update now, or whenever you like. Nothing installs by itself." }
        return "It installs by itself \(UpdatesNightLine.when(p.updateHour)), or now."
    }

    /// The step a failed run stopped at, from the updater's error code.
    static func failedStep(_ error: String?) -> CoreRun.Step {
        switch error {
        case "start_failed": .restart
        case "install_failed", "wrong_version", "bad_signature", "bad_manifest", "manifest_replayed",
            "manifest_expired",
            "no_manifest":
            .install
        default: .health
        }
    }

    static func list(_ names: [String]) -> String {
        names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}

/// The breath on the running step's icon, read with the page's Reduce Motion.
private struct StepBreath: ViewModifier {
    let on: Bool
    @Environment(\.updReduce) private var reduce
    func body(content: Content) -> some View {
        if on { content.modifier(UpdBreath(reduce: reduce)) } else { content }
    }
}
