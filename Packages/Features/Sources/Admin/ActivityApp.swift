import CoreUI
import Foundation
import Shell
import SwiftUI

// The Secrets and Activity apps (E2-6): each is a pane of its own now, no longer a Settings section. Secrets is the same
// list as before with the page title and a line on where account keys live. Activity is Ops and Audit under two tabs, with a
// live badge, a strip of what is running now, summary cards with a trend, and audit rows that rise in. Every motion has a
// still state under Reduce Motion, and none follows the pointer.

enum ActivityTab: String, Hashable, Sendable { case ops, audit }

// MARK: - what the apps show, as pure values

/// One figure in the "running now" strip.
struct StripItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

extension OpsModel {
    static let stripNames = [
        "ainkrad_agent_sessions", "ainkrad_terminals", "ainkrad_runners", "ainkrad_devices_active",
    ]

    /// What is running now, in the order of `stripNames`, only what the Core reported.
    var strip: [StripItem] {
        Self.stripNames.compactMap { n in
            tiles.first { $0.name == n }.map { StripItem(id: $0.name, title: $0.title, value: $0.value) }
        }
    }
}

/// The four numbers over the audit rows that are loaded.
struct AuditSummary: Equatable {
    var total = 0
    var today = 0
    var secrets = 0
    /// Rows nobody was watching for: schedules, Brain, AI sessions, the Core itself.
    var unattended = 0
}

extension AuditModel {
    static func summary(_ items: [AuditItem], now: Date, calendar: Calendar = .current) -> AuditSummary {
        AuditSummary(
            total: items.count,
            today: items.filter { calendar.isDate($0.at, inSameDayAs: now) }.count,
            secrets: items.filter { $0.action.hasPrefix("secret.") }.count,
            unattended: items.filter { $0.origin?.watched == false }.count)
    }

    /// Rows per slice for the ones `keep` accepts, across the span of all loaded rows, scaled 0...1 by the busiest slice.
    /// Empty when the loaded rows span no time (a trend needs two points).
    static func trend(_ items: [AuditItem], count: Int = 16, where keep: (AuditItem) -> Bool) -> [Double] {
        guard let first = items.map(\.at).min(), let last = items.map(\.at).max(), first < last, count > 1 else {
            return []
        }
        let slice = last.timeIntervalSince(first) / Double(count)
        return heatBuckets(items.filter(keep).map(\.at), now: last, slice: slice, count: count)
    }
}

extension AdminModel {
    /// A link from another app (a connection's History) put an audit filter in the hand-off: show exactly those rows.
    func takeHandoff() {
        let s = host.shell.settings
        guard let kind = s.handoff["audit.kind"] else { return }
        let target = s.handoff["audit.target"] ?? ""
        s.handoff = [:]
        activityTab = .audit
        audit.open(kind: kind, target: target)
        Task { await audit.reload() }
    }

    func showSecrets() {
        var spec = PaneSpec(id: "secrets", title: "Secrets", sub: "Home Core", symbol: "key", minWidth: 720) {
            SecretsApp(admin: self)
        }
        spec.tab = "Secrets"
        host.shell.openPane(spec)
    }

    func showActivity(_ tab: ActivityTab? = nil) {
        if let tab { activityTab = tab }
        var spec = PaneSpec(
            id: "activity", title: "Activity", sub: "Home Core", symbol: "waveform.path.ecg", minWidth: 760
        ) { ActivityApp(admin: self) }
        spec.tab = "Activity"
        host.shell.openPane(spec)
    }
}

// MARK: - Secrets

struct SecretsApp: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Secrets").coreFont(size: MacTextSize.large, weight: .bold)
                    Text("Passwords and keys you keep for yourself. Keys for AI accounts live in Accounts.")
                        .foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
                SecretsSection(admin: admin)
                Label(
                    "Storing, replacing, showing, exporting or handing out a secret asks for Touch ID first.",
                    systemImage: "lock"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            }
            .coreFont(size: MacTextSize.body)
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .accessibilityIdentifier("secrets-app")
    }
}

// MARK: - Activity

struct ActivityApp: View {
    let admin: AdminModel

    var body: some View {
        let tab = Binding(get: { admin.activityTab }, set: { admin.activityTab = $0 })
        VStack(alignment: .leading, spacing: 0) {
            AppHeader {
                CoreTabs(
                    "Activity",
                    tabs: [CoreTab(ActivityTab.ops, "Ops"), CoreTab(ActivityTab.audit, "Audit")],
                    selection: tab)
            } actions: {
                LiveBadge(readAt: admin.ops.readAt, live: admin.isConnected)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    LiveStrip(items: admin.ops.strip)
                    LiveNow(events: admin.liveEvents)
                    switch admin.activityTab {
                    case .ops:
                        OpsHostCards(admin: admin)
                        OpsSection(admin: admin)
                    case .audit:
                        AuditCards(model: admin.audit)
                        if !admin.audit.stats.isEmpty {
                            AuditHeatmap(model: admin.audit)
                            AuditKindBars(model: admin.audit)
                        }
                        AuditSection(admin: admin)
                    }
                }
                .coreFont(size: MacTextSize.body)
                .foregroundStyle(GlassInk.primary)
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .task {
            admin.takeHandoff()
            await admin.audit.reloadStats()
            // The Core reports the present value only: reading again while this app is open is what draws the charts.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                await admin.ops.reload()
                await admin.audit.reloadStats()
            }
        }
        .onChange(of: admin.host.shell.settings.handoff) { admin.takeHandoff() }
        .accessibilityIdentifier("activity-app")
    }
}

/// "Live" with a soft pulse while the Core is connected, and when this Mac last read it. Still under Reduce Motion.
private struct LiveBadge: View {
    let readAt: Date?
    let live: Bool
    @State private var beat = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: Space.s2) {
            coreShape(2).fill(live ? GlassInk.green : GlassInk.slate)
                .frame(width: Space.s2, height: Space.s2)
                .opacity(live && beat && !reduce ? 0.35 : 1)
            Text(live ? "Live" : "Not connected").coreFont(size: MacTextSize.meta, weight: .semibold)
            if live, let readAt {
                Text("Read \(AdminWords.time(readAt))").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(palette.text2)
            }
        }
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlSm)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeInOut(duration: Motion.tick).repeatForever(autoreverses: true)) { beat = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(live ? "Live" : "Not connected")
    }
}

/// What is running right now: one chip per figure the Core reported. The number rolls when it changes.
private struct LiveStrip: View {
    let items: [StripItem]
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: Space.s3) {
                Text("Happening now").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(palette.text2)
                ForEach(items) { i in
                    HStack(spacing: Space.s2) {
                        Text(i.value).coreFont(size: MacTextSize.headline, weight: .bold, design: .rounded)
                            .contentTransition(.numericText())
                        Text(i.title).foregroundStyle(palette.text2)
                    }
                    .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
                    .background(GlassInk.well, in: coreShape(Radius.control))
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
            .animation(reduce ? nil : Motion.out(Motion.move), value: items)
        }
    }
}

/// Four numbers over the loaded audit rows, each with a small trend. They count up when they change.
private struct AuditCards: View {
    @Bindable var model: AuditModel

    var body: some View {
        let items = model.items
        if !model.stats.isEmpty {
            let days = model.stats
            let day = days[min(model.selectedDay, days.count - 1)]
            let when = model.selectedDay == 0 ? "today" : ActivityStats.dayLabel(day.date, index: model.selectedDay)
            HStack(alignment: .top, spacing: Space.s3) {
                StatCard(
                    index: 0, title: "Actions \(when)", value: day.total,
                    series: ActivityStats.series(days) { $0.total },
                    tone: .run)
                StatCard(
                    index: 1, title: "AI sessions \(when)", value: day.count("sessions"),
                    series: ActivityStats.series(days) { $0.count("sessions") }, tone: .run)
                StatCard(
                    index: 2, title: "Secrets \(when)", value: day.count("secrets"),
                    series: ActivityStats.series(days) { $0.count("secrets") }, tone: .run)
                StatCard(
                    index: 3, title: "Needed a look \(when)", value: day.needsAttention,
                    series: ActivityStats.series(days) { $0.needsAttention }, tone: .warn)
            }
        } else if !items.isEmpty {
            let s = AuditModel.summary(items, now: Date())
            HStack(alignment: .top, spacing: Space.s3) {
                card(0, "Actions", s.total, AuditModel.trend(items) { _ in true })
                card(1, "Today", s.today, AuditModel.trend(items) { Calendar.current.isDateInToday($0.at) })
                card(2, "Secrets", s.secrets, AuditModel.trend(items) { $0.action.hasPrefix("secret.") })
                card(
                    3, "Nobody watching", s.unattended, AuditModel.trend(items) { $0.origin?.watched == false },
                    tone: .warn)
            }
        }
    }

    private func card(_ i: Int, _ title: String, _ n: Int, _ series: [Double], tone: Tone = .run) -> some View {
        StatCard(index: i, title: title, value: n, series: series, tone: tone)
    }
}

private struct StatCard: View {
    let index: Int
    let title: String
    let value: Int
    let series: [Double]
    let tone: Tone
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            Text("\(value)").coreFont(size: MacTextSize.large, weight: .bold, design: .rounded)
                .contentTransition(.numericText(value: Double(value)))
            if series.count >= 2 {
                CoreSpark(series, tone: tone).chartReveal()
            } else {
                Spacer().frame(height: Space.s6 + Space.s2)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .modifier(RiseIn(index: index))
        .animation(reduce ? nil : Motion.out(Motion.move), value: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// An entrance: the view slides up a few points and fades in once, the first ones a beat after each other. It does nothing
/// under Reduce Motion, and it never reacts to the pointer.
struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : Space.s2)
            .onAppear {
                guard !shown, !reduce else { return }
                // Only the first dozen wait their turn; a row that scrolls into view rises at once.
                let wait = index < 12 ? Double(index) * Motion.stagger : 0
                withAnimation(Motion.out(Motion.move).delay(wait)) { shown = true }
            }
    }
}
