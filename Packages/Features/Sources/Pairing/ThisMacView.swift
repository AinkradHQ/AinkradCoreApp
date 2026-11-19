import CoreUI
import Darwin
import Foundation
import Shell
import SwiftUI

/// This Mac's own memory and disk, read here: the runner does not report them, and they are this Mac's to read.
struct MacVitals: Equatable, Sendable {
    var memory: Double?
    var disk: Double?

    static func read() -> MacVitals { MacVitals(memory: memoryUsed(), disk: diskUsed()) }

    /// Active, wired and compressed pages over all memory, 0...1.
    static func memoryUsed() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = Double(pages) * Double(getpagesize())
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }

    /// The startup volume's used share, 0...1.
    static func diskUsed() -> Double? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
            let total = v.volumeTotalCapacity, total > 0, let free = v.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return min(1, max(0, 1 - Double(free) / Double(total)))
    }
}

/// The This Mac tab (mockup 12): one big switch, four stats, the tools, two options and two actions.
struct ThisMacView: View {
    let app: AppModel
    @State private var vitals = MacVitals()
    @Environment(\.corePalette) private var palette

    private var model: MacRunnerModel { app.macRunner }
    private var runnerID: String? { model.deviceID }
    private var connected: Bool? { runnerID.flatMap { app.terminals?.isOnline(runner: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("This Mac").coreFont(size: MacTextSize.title, weight: .semibold).accessibilityAddTraits(.isHeader)
                Text("Let Core use this Mac to run work while you are away.").foregroundStyle(palette.text2)
            }
            big
            MacRunnerStatus(
                model: model, accounts: runnerID.flatMap { app.terminals?.accountsAnswer(forRunner: $0) },
                connected: connected)
            stats
            HStack(alignment: .top, spacing: Space.s3) {
                tools
                options
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                Button {
                    model.showLog()
                } label: {
                    Label("Show what it did", systemImage: "doc.text")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!model.isAvailable)
                Button {
                    Task { await model.restart() }
                } label: {
                    Label("Restart runner", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(!model.isAvailable || !model.useThisMac || model.isBusy)
            }
        }
        .task {
            while !Task.isCancelled {
                vitals = MacVitals.read()
                await app.terminals?.recheck()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var statusLine: String {
        if !model.isAvailable { return "This build has no runner inside." }
        if !model.useThisMac { return "Off. Core will not send work to this Mac." }
        return connected == true
            ? "\(model.runnerName) is online and ready." : "\(model.runnerName) is starting. Core has not heard from it yet."
    }

    private var big: some View {
        HStack(spacing: Space.s4) {
            IconTile("laptopcomputer", hue: model.useThisMac && connected == true ? GlassInk.green : GlassInk.slate, size: 56)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Work for Core").coreFont(size: MacTextSize.large, weight: .semibold)
                Text(statusLine).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            if let id = runnerID, let s = app.terminals?.loadSamples(ofRunner: id), s.count >= 2, model.useThisMac {
                CoreSpark(s, ceiling: max(0.5, s.max() ?? 0.5)).frame(width: 120, height: 34)
                    .accessibilityLabel("Load on this Mac, last ten minutes")
            }
            CoreSwitch(
                "", isOn: Binding(get: { model.useThisMac }, set: { v in Task { await model.setUseThisMac(v) } })
            )
            .disabled(!model.isAvailable || model.isBusy)
            .accessibilityLabel("Work for Core")
            .accessibilityIdentifier("mac-runner-switch")
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
    }

    private var stats: some View {
        let version = runnerID.flatMap { app.terminals?.version(ofRunner: $0) }
        let update = runnerID.flatMap { app.terminals?.updateAvailable(ofRunner: $0) }
        return HStack(spacing: Space.s3) {
            stat("Connection", connected == true ? "Online" : model.useThisMac ? "Not connected" : "Off", nil, nil)
            stat("Version", version ?? "Not reported", update == nil ? nil : update == true ? "Update available" : "Up to date", nil)
            stat("Memory", vitals.memory.map(Self.percent) ?? "Not reported", nil, vitals.memory)
            stat("Disk", vitals.disk.map(Self.percent) ?? "Not reported", nil, vitals.disk)
        }
    }

    private func stat(_ title: String, _ value: String, _ note: String?, _ share: Double?) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
            Text(value).coreFont(size: MacTextSize.title, weight: .semibold).monospacedDigit()
            if let share { CoreMeter(share, low: share > 0.9, label: "\(title) \(value)") }
            if let note { Text(note).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2) }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreWell()
        .accessibilityElement(children: .combine)
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private var tools: some View {
        let ready = runnerID.map { app.terminals?.tools(ofRunner: $0) ?? [] } ?? []
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("Tools").coreFont(size: MacTextSize.headline, weight: .semibold)
            HStack(spacing: Space.s1) {
                ForEach(["Claude", "Codex", "OpenCode", "Antigravity"], id: \.self) { n in
                    ToolPill(name: n, on: ready.contains(n.lowercased()))
                }
            }
            Text(model.problem.map { "Last problem: \($0)" } ?? "Last problem: none.")
                .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Installed and updated for you.").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Options").coreFont(size: MacTextSize.headline, weight: .semibold)
            option(
                "Terminals on this Mac", MacRunnerModel.terminalsWarning,
                Binding(get: { model.terminals }, set: { v in Task { await model.setTerminals(v) } })
            )
            .disabled(!model.isAvailable || !model.useThisMac || model.isBusy)
            option(
                "Keep this Mac awake while working", "Only while a task is running.",
                Binding(get: { model.keepAwake }, set: { model.setKeepAwake($0) }))
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .topLeading)
        .coreWell()
    }

    private func option(_ title: String, _ sub: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(sub).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            CoreSwitch("", isOn: on).accessibilityLabel(title)
        }
    }
}

/// A tool as a small rounded tag: lit when installed, quiet when not.
private struct ToolPill: View {
    let name: String
    let on: Bool
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(name).coreFont(size: MacTextSize.meta, weight: .medium).lineLimit(1).fixedSize()
            .foregroundStyle(on ? GlassInk.primary : palette.text2.opacity(0.6))
            .padding(.horizontal, Space.s2).frame(height: MacSize.chip)
            .background(on ? GlassInk.well : .clear, in: coreShape(Radius.control))
            .accessibilityLabel(on ? "\(name) ready" : "\(name) not installed")
    }
}

/// The About tab (mockup 12): the Core's name and version, what it runs on, and a check for updates.
struct AboutTabView: View {
    @Environment(\.coreAccent) private var paneAccent
    let app: AppModel
    @State private var checking = false
    @Environment(\.corePalette) private var palette

    private var version: String? { app.about.about?.server }
    private var mine: String? { app.macRunner.runnerID }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(spacing: Space.s2) {
                IconTile("server.rack", hue: GlassInk.accent(paneAccent), size: 64)
                Text("Ainkrad Core").coreFont(size: MacTextSize.title, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(version.map { "Version \($0)" } ?? "Version not reported yet").foregroundStyle(palette.text2)
            }
            .frame(maxWidth: .infinity).padding(.top, Space.s4)
            VStack(alignment: .leading, spacing: Space.s3) {
                row("Core address", app.shell.home.coreName)
                row("This Mac", mine.flatMap { id in app.terminals?.version(ofRunner: id).map { "\(app.macRunner.runnerName) · runner \($0)" } } ?? "Not a runner")
                row("Running for", app.shell.home.health?.uptime ?? "Not reported yet")
                row("Tools it keeps current", toolLine)
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).coreWell()
            HStack {
                Spacer()
                Button {
                    Task { await check() }
                } label: {
                    Label("Check for updates", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(checking)
                Spacer()
            }
            AboutBlock(app: app)
        }
    }

    private var toolLine: String {
        let line = mine.flatMap { app.terminals?.toolLine(ofRunner: $0) } ?? ""
        return line.isEmpty ? "Not reported yet" : line
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(title).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).frame(width: 160, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// Looks again at the Core and its runners. The Core has no update service yet (E12), so this says what the Core
    /// and its runners report: the version it runs and how many runners have an update waiting.
    private func check() async {
        checking = true
        defer { checking = false }
        let me = await app.about.reload()
        await app.terminals?.recheck()
        let waiting = app.terminals?.runnersWithUpdate ?? 0
        let core = me.map { "Core \($0.server) is running." } ?? "The Core did not answer."
        let runners = waiting == 0 ? "Every runner is up to date." : "\(waiting) \(waiting == 1 ? "runner has" : "runners have") an update."
        app.shell.showToast("\(core) \(runners)", kind: me == nil ? .error : .ok)
    }
}
