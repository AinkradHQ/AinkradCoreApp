import AppKit
import CoreUI
import SwiftUI

enum LogLevel: Equatable {
    case info, warning, error

    static func of(_ text: String) -> LogLevel {
        if LogWords.isError(text) || text.localizedCaseInsensitiveContains("missing") { return .error }
        let l = text.lowercased()
        return l.contains("warn") || l.contains("slow") || l.contains("deprecated") ? .warning : .info
    }
}

/// What the Logs page shows of a log: the rows of one service (all when nil) that hold the search words.
@MainActor enum LogView {
    static func rows(_ entries: [LogEntry], service: String?, query: String) -> [LogEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return entries.filter {
            switch $0.kind {
            case .skipped: service == nil && q.isEmpty
            case .line(let l):
                (service == nil || l.service == service) && (q.isEmpty || l.text.localizedCaseInsensitiveContains(q))
            }
        }
    }

    /// What Copy puts on the pasteboard: the rows shown, with their time and service.
    static func text(_ rows: [LogEntry]) -> String {
        rows.map {
            switch $0.kind {
            case .line(let l):
                [l.at.map(RunLogsModel.clock), l.service, l.text].compactMap { $0 }.joined(separator: " ")
            case .skipped(let n): "… \(RunLogsModel.gapWords(n))"
            }
        }.joined(separator: "\n")
    }
}

/// The Logs focused page (details v2): the whole log, by service, searchable, following the newest line.
struct ModuleLogs: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var run: RunPageModel
    @State private var logs: RunLogsModel?
    @State private var fixed: RunLogsModel?
    @State private var service: String?
    @State private var query = ""
    @State private var following = true
    @Environment(\.corePalette) private var palette

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _run = State(initialValue: RunPageModel(model: model, projectID: project.id))
    }

    private var live: Bool { run.status?.state == "running" || run.status?.state == "starting" }
    private var shownLog: RunLogsModel? { live ? logs ?? fixed : fixed ?? logs }
    private var names: [String] { run.spec?.services.map(\.name) ?? project.live?.services.map(\.name) ?? [] }

    var body: some View {
        let rows = shownLog.map { LogView.rows($0.entries, service: service, query: query) } ?? []
        ModulePage(title: "Logs", sub: live ? nil : LogWords.caption(project)) {
            if !names.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    CoreSegmented(
                        "Log service", segments: [CoreSegment<String?>(nil, "All")] + names.map { CoreSegment($0, $0) },
                        selection: $service)
                }
                .frame(maxWidth: Space.s8 * 14)
            }
            ModuleSearch(placeholder: "Search the log", text: $query)
            Button {
                following.toggle()
                if following { shownLog?.jumpToLatest() }
            } label: {
                Label("Follow", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(CoreButtonStyle(following ? .prominent : .secondary, size: .small))
            .help(following ? "Stop following the newest line" : "Follow the newest line").accessibilityValue(
                following ? "On" : "Off")
            CoreIconButton(symbol: "doc.on.doc", label: "Copy the visible lines") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(LogView.text(rows), forType: .string)
                model.host.shell.showToast("Log copied")
            }
            .disabled(rows.isEmpty)
        } content: {
            ModuleWell {
                if let m = shownLog, !m.entries.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        if let f = m.failure { CoreFieldError(f).padding(.horizontal, Space.s4) }
                        list(m, rows)
                    }
                } else {
                    ModuleQuiet(
                        symbol: "text.alignleft", title: "No logs yet",
                        line: "Lines appear here while the project runs, and the last run's stay after it stops.")
                }
            }
        }
        .task(id: project.id) { await run.watch() }
        .task(id: model.runTick) {
            if run.loaded {
                await run.load()
                await run.refreshRun()
            }
        }
        // The Core's stream while it runs; the stand-in's lines (Debug) or nothing otherwise.
        .task(id: "\(project.id) \(live) \(model.runTick)") {
            guard live, let m = run.makeLogs() else {
                logs = nil
                if fixed == nil, project.live?.logs.isEmpty == false {
                    fixed = RunLogsModel.fixed(project.live?.logs ?? [], lost: 0, times: true)
                }
                return
            }
            m.showTimes = true
            logs = m
            await m.run()
        }
    }

    private func list(_ m: RunLogsModel, _ rows: [LogEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if rows.isEmpty {
                        Text("No line matches \(query.isEmpty ? "this filter" : "“\(query)”").")
                            .foregroundStyle(GlassInk.secondary).padding(Space.s2)
                    }
                    ForEach(rows) { row($0) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            }
            .onChange(of: m.scrollTick) { _, _ in if following { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: following) { _, on in if on { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    @ViewBuilder private func row(_ e: LogEntry) -> some View {
        switch e.kind {
        case .line(let l):
            let level = LogLevel.of(l.text)
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(l.at.map(RunLogsModel.clock) ?? "").foregroundStyle(GlassInk.secondary).monospacedDigit()
                    .frame(width: 64, alignment: .leading)
                Text(l.service).foregroundStyle(GlassInk.secondary).lineLimit(1).frame(width: 64, alignment: .leading)
                Text(l.text).foregroundStyle(ink(level)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: MacTextSize.meta + 1, design: .monospaced))
            .padding(.vertical, 2).padding(.horizontal, Space.s2)
            .background(level == .error ? palette.tone(.fail).ink.opacity(0.12) : .clear, in: coreShape(Radius.chip))
            .accessibilityElement(children: .combine)
        case .skipped(let n):
            Label(RunLogsModel.gapWords(n), systemImage: "ellipsis").font(.system(size: MacTextSize.meta))
                .foregroundStyle(GlassInk.secondary).padding(Space.s2)
                .help("The runner could not keep up and dropped these lines before they were read")
        }
    }

    private func ink(_ l: LogLevel) -> Color {
        switch l {
        case .info: GlassInk.primary
        case .warning: palette.tone(.warn).ink
        case .error: palette.tone(.fail).ink
        }
    }
}
