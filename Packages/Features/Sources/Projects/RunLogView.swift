import AppKit
import CoreUI
import SwiftUI

/// A run's log on screen: the lines as they arrive, a search, the time of each line, Copy, a filter by service, and a
/// "Latest" button when the person has scrolled up (scrolling up pauses following; reaching the end or pressing it resumes).
struct RunLogView: View {
    let logs: RunLogsModel
    /// The services to filter by (the Core filters; nil is all).
    var services: [String] = []
    /// Show only the newest lines in a short box (the Overview), without the toolbar.
    var compact = false
    /// False when the page puts `RunLogToolbar` in its island header instead of above the lines.
    var toolbar = true
    var toast: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !compact && toolbar { RunLogToolbar(logs: logs, services: services, toast: toast) }
            if let f = logs.failure { CoreFieldError(f) }
            ZStack(alignment: .bottomTrailing) {
                list
                if !logs.follow && !compact {
                    Button {
                        logs.jumpToLatest()
                    } label: {
                        Label("Latest", systemImage: "arrow.down")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .padding(Space.s2)
                    .help("Follow the newest line again")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run log")
    }

    private var list: some View {
        let rows = compact ? Array(logs.shown.suffix(6)) : logs.shown
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if rows.isEmpty { Text(empty).foregroundStyle(GlassInk.secondary) }
                    ForEach(rows) { row($0) }
                    Color.clear.frame(height: 1).id("end")
                        .onAppear { logs.endVisible(true) }
                        .onDisappear { logs.endVisible(false) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(compact ? 0 : Space.s3)
            }
            .onChange(of: logs.scrollTick) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private var empty: String {
        if let s = logs.service, logs.search.isEmpty { return "Nothing from \(s) yet." }
        if !logs.search.isEmpty { return "No line matches “\(logs.search)”." }
        return logs.feed == .ended ? "The run ended with no output." : "No log lines yet."
    }

    @ViewBuilder private func row(_ e: LogEntry) -> some View {
        switch e.kind {
        case .line(let l):
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                if logs.showTimes, let at = l.at {
                    Text(RunLogsModel.clock(at)).foregroundStyle(GlassInk.secondary).monospacedDigit()
                }
                Text(l.service).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    .frame(width: Space.s8 * 2, alignment: .leading)
                Text(l.text).textSelection(.enabled).lineLimit(compact ? 1 : nil)
                    .foregroundStyle(LogLevel.of(l.text) == .error ? GlassInk.redInk : GlassInk.primary)
            }
            .font(.system(size: MacTextSize.meta, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        case .skipped(let n):
            Label(RunLogsModel.gapWords(n), systemImage: "ellipsis")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(GlassInk.secondary)
                .help("The runner could not keep up and dropped these lines before they were read")
        }
    }
}


/// A log's controls: the service filter, the search with its match count, the time of each line and Copy. It sits in the header
/// of the island that holds the log, so no band of its own stands empty above the lines.
struct RunLogToolbar: View {
    let logs: RunLogsModel
    var services: [String] = []
    var toast: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: Space.s2) {
            if !services.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    CoreSegmented(
                        "Log service", segments: [CoreSegment("", "All")] + services.map { CoreSegment($0, $0) },
                        selection: Binding(
                            get: { logs.service ?? "" }, set: { logs.setService($0.isEmpty ? nil : $0) })
                    )
                }
                .frame(maxWidth: Space.s8 * 14)
            }
            Spacer(minLength: 0)
            if let m = logs.matchLine { Text(m).foregroundStyle(GlassInk.secondary).monospacedDigit() }
            CoreTextField(
                "", placeholder: "Search the log", text: Binding(get: { logs.search }, set: { logs.search = $0 })
            )
            .frame(width: Space.s8 * 6)
            .accessibilityLabel("Search the log")
            CoreIconButton(
                symbol: "clock", label: logs.showTimes ? "Hide the time of each line" : "Show the time of each line",
                selected: logs.showTimes
            ) {
                logs.showTimes.toggle()
            }
            CoreIconButton(symbol: "doc.on.doc", label: "Copy the log") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logs.copyText, forType: .string)
                toast("Log copied")
            }
            .disabled(logs.entries.isEmpty)
        }
    }
}
