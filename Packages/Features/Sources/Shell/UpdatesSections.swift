import CoreUI
import SwiftUI

/// Runners: the Core host's runner first (it updates with the Core), then every other runner with its own state, one by
/// one under Update everything: Next → Asked → Updating → its new version. This Mac's runner is not here; it sits under
/// This Mac app because it comes inside the app.
struct UpdatesRunnersSection: View {
    let model: UpdatesModel
    let t: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Runners").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                .padding(.horizontal, Space.s1).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                if !model.supported {
                    note("This Core is too old to update its runners from here.")
                } else if model.listed.isEmpty {
                    note("No runners yet.")
                } else {
                    ForEach(Array(model.listed.enumerated()), id: \.element.id) { i, r in row(r, index: i) }
                }
            }
            .padding(Space.s1)
            .coreWell()
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).foregroundStyle(GlassInk.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(Space.s3)
    }

    private func row(_ r: UpdatableRunner, index: Int) -> some View {
        let state = model.state(r)
        let live = state == .asked || state == .updating
        return HStack(spacing: Space.s3 + 2) {
            UpdTile(size: 28, tint: nil) {
                Image(systemName: r.builtIn ? "server.rack" : "cpu").coreFont(size: MacTextSize.body, weight: .medium)
                    .foregroundStyle(GlassInk.secondary)
            }
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(r.name).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1).help(r.name)
                Text(sub(r, state)).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            side(r, state, index: index).updSwap(Self.key(state, running: model.run != nil))
                .frame(minWidth: 220, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3 + 2)
        .frame(minHeight: 50)
        .background(live ? GlassInk.accent(nil).opacity(0.16) : .clear, in: coreShape(Radius.control))
        .animation(Motion.out(Motion.ui), value: live)
        .accessibilityElement(children: .contain)
    }

    private static func key(_ s: RunnerUpdateState, running: Bool) -> String {
        "\(s)-\(s == .withCore && running)"
    }

    private func sub(_ r: UpdatableRunner, _ s: RunnerUpdateState) -> String {
        switch s {
        case .withCore: "Built into the Core · updates with it"
        case .withApp: "Comes inside the app, so it updates with the app"
        case .offline: "Offline · updates when it is back"
        case .queued: "Next, once the one before it is done"
        case .asked, .updating: "Its AI Sessions keep running elsewhere"
        case .behind: "A newer version is ready"
        case .upToDate: "Online"
        }
    }

    private var latest: String? { model.check?.latestRunner ?? model.run?.to ?? model.target ?? model.coreVersion }

    @ViewBuilder private func side(_ r: UpdatableRunner, _ s: RunnerUpdateState, index: Int) -> some View {
        let v = r.version ?? "Not reported"
        switch s {
        case .withCore:
            HStack(spacing: Space.s3) {
                if let run = model.run {
                    UpdVersions(from: v, to: run.to)
                    StateBadge("With the Core", tone: .done, symbol: "server.rack")
                } else {
                    Text(v).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary).monospacedDigit()
                    StateBadge(
                        r.behind ? "Updates with the Core" : "Up to date", tone: r.behind ? .queue : .run,
                        symbol: "checkmark")
                }
            }
        case .queued:
            HStack(spacing: Space.s3) {
                UpdVersions(from: v, to: latest)
                StateBadge("Next", tone: .queue, symbol: "clock")
            }
        case .behind:
            HStack(spacing: Space.s3) {
                UpdVersions(from: v, to: latest)
                if index < 9 {
                    Button {
                        Task { await model.update(runner: r.id) }
                    } label: {
                        Label("Update", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                    .environment(\.coreKeycap, "⌥\(index + 1)")
                    .disabled(model.pressed)
                    .accessibilityLabel("Update \(r.name)")
                }
            }
        case .asked, .updating:
            progress(r, asked: s == .asked)
        case .offline:
            HStack(spacing: Space.s3) {
                Text(v).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary).monospacedDigit()
                StateBadge("Offline", tone: .queue, symbol: "moon")
            }
        case .upToDate, .withApp:
            HStack(spacing: Space.s3) {
                Text(v).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary).monospacedDigit()
                StateBadge("Up to date", tone: .run, symbol: "checkmark")
            }
        }
    }

    /// Two short bars, Asked then Updating, with what is happening and the seconds left.
    private func progress(_ r: UpdatableRunner, asked: Bool) -> some View {
        let askedAt = model.asked[r.id] ?? t
        let since = model.updatingSince[r.id] ?? t
        let first = asked ? min(1, t.timeIntervalSince(askedAt) / 1.2) : 1
        // ponytail: a runner's update has no progress of its own; 30 s is a typical swap, held at 92 % until it is back.
        let second = asked ? 0 : min(0.92, t.timeIntervalSince(since) / 30)
        let left = max(1, Int((30 - t.timeIntervalSince(since)).rounded(.up)))
        return VStack(alignment: .leading, spacing: Space.s1 + 2) {
            HStack(spacing: Space.s1) {
                UpdBar(value: first, look: asked ? .accent : .done, height: 4)
                UpdBar(value: second, height: 4)
            }
            HStack {
                Text(asked ? "Asked \(r.name) to update…" : "Updating to \(latest ?? "the new version")")
                Spacer(minLength: Space.s2)
                if !asked { Text("About \(left) s left").monospacedDigit() }
            }
            .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
        }
        .frame(width: 260)
        .accessibilityElement(children: .combine)
    }
}

/// This Mac app: its version and Sparkle's download (in the background, then ready to install on restart), and the
/// runner that comes inside it. That runner never has an Update button: it updates with the app.
struct UpdatesMacSection: View {
    let model: UpdatesModel
    let t: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("This Mac app").coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.secondary)
                .padding(.horizontal, Space.s1).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Space.s3) {
                row(symbol: "laptopcomputer", title: "Ainkrad \(model.appVersion)", sub: appSub) {
                    if model.appReady != nil {
                        StateBadge("Ready to install", tone: .done, symbol: "arrow.down.to.line")
                    } else if model.appDownloading != nil {
                        StateBadge("Downloading", tone: .done, symbol: "arrow.down")
                    } else {
                        HStack(spacing: Space.s3) {
                            Text(model.appVersion).coreFont(size: MacTextSize.meta + 1)
                                .foregroundStyle(GlassInk.secondary).monospacedDigit()
                            StateBadge("Up to date", tone: .run, symbol: "checkmark")
                        }
                    }
                }
                .updSwap("\(model.appDownloading ?? "")-\(model.appReady ?? "")")
                if model.appDownloading != nil, model.appReady == nil {
                    VStack(alignment: .leading, spacing: Space.s1 + 2) {
                        UpdBar(value: 0, waiting: true)
                        Text("Downloading in the background. Keep working.").coreFont(size: MacTextSize.meta + 1)
                            .foregroundStyle(GlassInk.secondary)
                    }
                    .transition(.opacity)
                }
                row(
                    symbol: "cpu", title: "This Mac's runner", sub: "Comes inside the app, so it updates with the app"
                ) {
                    HStack(spacing: Space.s1) {
                        UpdVersions(from: model.macRunner?.version ?? model.appVersion, to: model.appReady)
                        Text("· with the app")
                    }
                    .coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
                }
            }
            .padding(Space.s4)
            .coreWell()
        }
    }

    private var appSub: String {
        if let v = model.appReady {
            return "\(v) is downloaded. It installs when you restart the app, or when you quit it."
        }
        if let v = model.appDownloading { return "Downloading \(v) in the background. Keep working." }
        return "Updates download by themselves and wait for you to restart."
    }

    private func row<Side: View>(symbol: String, title: String, sub: String, @ViewBuilder side: () -> Side) -> some View
    {
        HStack(spacing: Space.s3 + 2) {
            UpdTile(size: 28, tint: nil) {
                Image(systemName: symbol).coreFont(size: MacTextSize.body, weight: .medium)
                    .foregroundStyle(GlassInk.secondary)
            }
            VStack(alignment: .leading, spacing: Space.s1 / 2) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(sub).coreFont(size: MacTextSize.meta + 1).foregroundStyle(GlassInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            side()
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Updates also install by themselves at night, around 3:00. Change…": Change opens the switch and the hour.
struct UpdatesNightLine: View {
    let shell: ShellModel
    @State private var open = false
    @Environment(\.coreAccent) private var accent

    static func when(_ hour: Int) -> String {
        switch hour {
        case 0...5: "at night, around \(hour):00"
        case 6...11: "in the morning, around \(hour):00"
        case 12...17: "in the afternoon, around \(hour):00"
        default: "in the evening, around \(hour):00"
        }
    }

    var body: some View {
        let p = shell.corePage.prefs
        HStack(spacing: Space.s2) {
            Image(systemName: "clock").accessibilityHidden(true)
            Text(
                !shell.corePage.supported
                    ? "This Core is too old to install updates by itself."
                    : p.autoUpdate
                        ? "Updates also install by themselves \(Self.when(p.updateHour))."
                        : "Updates install only when you choose."
            )
            if shell.corePage.supported {
                Button("Change…") { open.toggle() }
                    .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    .keyboardShortcut("n", modifiers: [.command, .option]).environment(\.coreKeycap, "⌥⌘N")
                    .popover(isPresented: $open, arrowEdge: .bottom) { choices.padding(Space.s4).frame(width: 360) }
            }
        }
        .coreFont(size: MacTextSize.meta + 1)
        .foregroundStyle(GlassInk.secondary)
        .padding(.horizontal, Space.s1)
    }

    /// Where an update may install: the stored hour always shows, even when it is not one of these.
    private var hours: [CoreSelectOption<Int>] {
        var list = [(3, "Night, around 3:00"), (6, "Early morning, around 6:00"), (22, "Late evening, around 22:00")]
        let now = shell.corePage.prefs.updateHour
        if !list.contains(where: { $0.0 == now }) { list.append((now, "Around \(now):00")) }
        return list.map { CoreSelectOption($0.0, $0.1) }
    }

    private var choices: some View {
        VStack(spacing: Space.s2) {
            CoreRow(
                "Update by themselves", subtitle: "The Core and the runners",
                trailing: {
                    CoreSwitch(
                        isOn: Binding(
                            get: { shell.corePage.prefs.autoUpdate },
                            set: { on in Task { await shell.corePage.save(autoUpdate: on) } }))
                })
            CoreRow(
                "Install at", subtitle: "Core restarts for a few seconds",
                trailing: {
                    CoreSelect(
                        nil,
                        selection: Binding(
                            get: { shell.corePage.prefs.updateHour },
                            set: { hour in Task { await shell.corePage.save(updateHour: hour) } }),
                        options: hours
                    )
                    .frame(width: Space.s8 * 5)
                })
        }
        .foregroundStyle(GlassInk.primary)
    }
}
