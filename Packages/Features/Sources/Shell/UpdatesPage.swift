import CoreUI
import SwiftUI

/// Settings, Updates (approved mockup `Designs/core/0-10/review/updates`, 2026-11-21): when it was checked, the version
/// map (this Mac app, the Core, the runners, joined by lines that pulse while something moves and break while the Core
/// restarts), the one card that says what is going on, the runners, this Mac app, and the night line.
/// Keys: ⌘R checks, ⌘U updates everything (or tries again), ⌘I what is new, ⌘L what happened, ⇧⌘R restarts this app to
/// install, ⌥⌘R later, ⌥1… updates one runner, ⌥⌘N changes the night time.
struct UpdatesPage: View {
    @Bindable var shell: ShellModel
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    var model: UpdatesModel { shell.updates }

    private var reduce: Bool {
        #if DEBUG
        if model.debugReduceMotion { return true }
        #endif
        return systemReduce
    }

    /// Anything moving: the page redraws four times a second for the bars, the seconds and the countdown.
    private var live: Bool {
        model.run != nil || !model.asked.isEmpty || !model.updatingSince.isEmpty || model.retryAt != nil
            || model.appDownloading != nil
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !live)) { _ in
            let t = model.now()
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                UpdatesMap(shell: shell, t: t)
                UpdatesHeroCard(shell: shell, t: t)
                UpdatesRunnersSection(model: model, t: t)
                UpdatesMacSection(model: model, t: t)
                UpdatesNightLine(shell: shell)
            }
        }
        .environment(\.updReduce, reduce)
        .foregroundStyle(GlassInk.primary)
        .task { await shell.corePage.load() }
        .task { await model.watch() }
    }

    private var header: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(model.checkWords(lastChecked: shell.corePage.prefs.updateCheckedAt))
                    .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                    .updSwap(model.checking)
                if let why = model.failure {
                    Text(why).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: Space.s2)
            Button {
                Task { await model.checkNow() }
                model.checkApp?()
            } label: {
                Label(model.checking ? "Checking…" : "Check now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CoreButtonStyle(.secondary, busy: model.checking))
            .keyboardShortcut("r").environment(\.coreKeycap, "⌘R")
            .disabled(!model.supported || model.checking || model.run != nil)
        }
        .animation(UpdMotion.swap(reduce), value: model.failure)
    }
}

/// The three tiles and the two lines between them.
struct UpdatesMap: View {
    let shell: ShellModel
    let t: Date
    @Environment(\.coreAccent) private var accent

    private var model: UpdatesModel { shell.updates }
    private var gap: Bool { model.run?.gapSince != nil }

    var body: some View {
        let run = model.run
        HStack(alignment: .top, spacing: 0) {
            node(
                "This Mac app", symbol: "laptopcomputer", from: model.appVersion,
                to: model.appReady ?? model.appDownloading, badge: macBadge,
                lit: model.appReady != nil || model.appDownloading != nil, pop: 0)
            UpdLink(
                flow: (run != nil && !gap) || model.appDownloading != nil, reverse: run == nil, gap: gap,
                label: run?.gapSeconds(at: t).map { "Reconnecting · \($0) s" }
            )
            .frame(height: 52)
            node(
                "Core", symbol: "server.rack", from: run?.from ?? coreVersion, to: run?.to ?? model.target,
                badge: coreBadge,
                lit: run != nil || model.target != nil, pop: 1
            ) {
                if let run {
                    UpdBar(value: run.progress(at: t), height: 4, waiting: gap).frame(width: 96)
                        .transition(.opacity)
                }
            }
            .opacity(gap ? 0.5 : 1)
            .animation(Motion.out(Motion.move), value: gap)
            UpdLink(flow: runnersBusy || (run.map { $0.step.rawValue >= 1 } ?? false && !gap)).frame(height: 52)
            node(
                "Runners", symbol: "cpu", from: runnersFrom, to: runnersTo, badge: runnersBadge, lit: runnersBusy,
                pop: 2)
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity)
        .coreWell()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Versions")
    }

    private var coreVersion: String {
        model.coreVersion ?? shell.home.health?.version ?? "…"
    }

    private var macBadge: (String, Tone) {
        if gap { return ("Reconnecting…", .warn) }
        if model.appReady != nil { return ("Ready to install", .done) }
        if model.appDownloading != nil { return ("Downloading", .done) }
        return ("Up to date", .run)
    }

    private var coreBadge: (String, Tone) {
        if model.run != nil { return gap ? ("Restarting", .warn) : ("Updating", .done) }
        if model.hero == .wentBack { return ("Went back", .fail) }
        if model.target != nil { return ("Update ready", .done) }
        return ("Up to date", .run)
    }

    private var busy: UpdatableRunner? {
        model.otherRunners.first { [.asked, .updating].contains(model.state($0)) }
    }
    private var runnersBusy: Bool { busy != nil }

    private var runnersFrom: String {
        let vs = model.listed.compactMap(\.version)
        return vs.min { $0.compare($1, options: .numeric) == .orderedAscending } ?? "None"
    }

    private var runnersTo: String? {
        let vs = model.listed.compactMap(\.version)
        guard let top = vs.max(by: { $0.compare($1, options: .numeric) == .orderedAscending }), top != runnersFrom
        else { return nil }
        return top
    }

    private var runnersBadge: (String, Tone) {
        let queued = model.queue.count - (busy == nil ? 0 : 1)
        if let busy { return (queued > 0 ? "Updating · \(queued) to go" : "Updating \(busy.name)", .done) }
        if queued > 0 { return ("\(queued) to follow", .done) }
        if model.run != nil { return ("Following the Core", .done) }
        let behind = model.behind.count
        if behind > 0 { return (behind == 1 ? "1 behind" : "\(behind) behind", .done) }
        return (model.listed.isEmpty ? "None yet" : "All up to date", .run)
    }

    private func node(
        _ name: String, symbol: String, from: String, to: String?, badge: (String, Tone), lit: Bool, pop: Int
    ) -> some View { node(name, symbol: symbol, from: from, to: to, badge: badge, lit: lit, pop: pop) { EmptyView() } }

    private func node<Extra: View>(
        _ name: String, symbol: String, from: String, to: String?, badge: (String, Tone), lit: Bool, pop: Int,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        VStack(spacing: Space.s2) {
            UpdTile(size: 52, tint: lit ? GlassInk.accent(accent) : nil) {
                Image(systemName: symbol).coreFont(size: 24, weight: .medium)
                    .foregroundStyle(lit ? GlassInk.accentInk(accent) : GlassInk.secondary)
            }
            .modifier(UpdPop(trigger: model.finished, delay: Double(pop) * UpdMotion.stagger))
            .modifier(UpdPop(trigger: pop == 1 ? model.coreVersion : nil, delay: 0))
            Text(name).coreFont(size: MacTextSize.body, weight: .semibold).padding(.top, Space.s1)
            UpdVersions(from: from, to: to, size: MacTextSize.large, weight: .semibold)
                .updSwap("\(from)>\(to ?? "")")
            StateBadge(badge.0, tone: badge.1, symbol: "circle").updSwap(badge.0)
            extra()
        }
        .frame(width: 190)
        .accessibilityElement(children: .combine)
    }
}
