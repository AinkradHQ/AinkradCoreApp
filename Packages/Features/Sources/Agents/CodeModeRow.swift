import CoreUI
import Foundation
import Shell
import SwiftUI

/// Which Code Mode tool a transcript row is. Claude names an MCP tool `mcp__ainkrad__ainkrad_run`, other harnesses use the bare name.
enum CodeModeTool: Equatable {
    case run, search

    static func of(_ name: String) -> CodeModeTool? {
        if name == "ainkrad_run" || name.hasSuffix("__ainkrad_run") { return .run }
        if name == "ainkrad_search" || name.hasSuffix("__ainkrad_search") { return .search }
        return nil
    }
}

/// What a finished `ainkrad_run` said: the value, the console lines, the `[N calls, M ms]` footer, and for a failure the
/// message, the line and the Core's refusal code (`error: … (line 3) [rate_limited]`).
struct CodeModeResult: Equatable {
    var value = ""
    var console = ""
    var calls: Int?
    var ms: Int?
    var message: String?
    var line: Int?
    var code: String?

    var footer: String? { calls.map { "[\($0) \($0 == 1 ? "call" : "calls"), \(ms ?? 0) ms]" } }

    static func parse(_ output: String) -> CodeModeResult {
        var r = CodeModeResult()
        var body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = body.range(of: #"\[(\d+) calls?, (\d+) ms\]$"#, options: .regularExpression) {
            let nums = body[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            r.calls = nums.first
            r.ms = nums.last
            body = String(body[..<m.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let c = body.range(of: "\nconsole:\n") {
            r.console = String(body[c.upperBound...])
            body = String(body[..<c.lowerBound])
        }
        if body.hasPrefix("error: ") {
            var msg = String(body.dropFirst(7))
            if let m = msg.range(of: #" \[([a-z_]+)\]$"#, options: .regularExpression) {
                r.code = String(msg[m]).trimmingCharacters(in: CharacterSet(charactersIn: " []"))
                msg = String(msg[..<m.lowerBound])
            }
            if let m = msg.range(of: #" \(line (\d+)\)$"#, options: .regularExpression) {
                r.line = Int(msg[m].filter(\.isNumber))
                msg = String(msg[..<m.lowerBound])
            }
            r.message = msg
        } else {
            r.value = body
        }
        return r
    }

    /// One short line of the answer for the collapsed row.
    var summary: String {
        if let code { return CodeModeWords.refusal(code) }
        if let message { return message }
        let first = value.split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty || first == "null" ? "Finished" : String(first.prefix(120))
    }
}

/// An `ainkrad_run` script or an `ainkrad_search` call as one compact row: closed it says what it did and how long it took,
/// open it shows the script and what came back. A refusal says why in words. Bodies of operations never show here.
struct CodeModeCard: View {
    enum Status: Equatable {
        case running
        case done
        case failed
    }
    let tool: CodeModeTool
    /// The script, or the search words.
    let summary: String
    let status: Status
    let output: String
    let durationMs: Int?
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.corePalette) private var palette

    private var result: CodeModeResult { CodeModeResult.parse(output) }
    private var title: String {
        switch (tool, status) {
        case (.run, .running): "Running a script"
        case (.run, .done): "Ran a script"
        case (.run, .failed): "A script stopped"
        case (.search, .running): "Searching the operations"
        case (.search, .done): "Searched the operations"
        case (.search, .failed): "A search failed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduce ? nil : Motion.out(Motion.ui)) { expanded.toggle() }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "chevron.right").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(palette.text2).rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: Space.s3)
                    Image(systemName: tool == .run ? "curlybraces" : "magnifyingglass").foregroundStyle(palette.primary)
                        .frame(width: Space.s4)
                    Text(title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                        .layoutPriority(1)
                    if status != .running {
                        Text(tool == .search ? "“\(summary)”" : result.summary)
                            .coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: Space.s2)
                    trailing
                }
                .padding(.horizontal, Space.s3).frame(minHeight: MacSize.controlLg)
                .contentShape(Rectangle())
            }
            .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
            .help(tool == .run ? "An AI session ran a script" : "An AI session searched the operations")
            if expanded { detail.transition(reduce ? .opacity : .opacity.combined(with: .offset(y: -Space.s1))) }
        }
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity)
        .clipShape(coreShape(Radius.control))
        .coreWell(radius: Radius.control)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(status == .running ? "" : result.summary)")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if tool == .run, !summary.isEmpty { block("Script", summary) }
            if tool == .search, !summary.isEmpty { block("Looked for", summary) }
            if status == .failed, let code = result.code {
                Label(CodeModeWords.refusal(code), systemImage: "exclamationmark.circle")
                    .coreFont(size: MacTextSize.body).foregroundStyle(palette.tone(.fail).ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status == .failed, result.code == nil, let m = result.message {
                block("What it said", m + (result.line.map { " (line \($0))" } ?? ""))
            } else if status == .done, !result.value.isEmpty, result.value != "null" {
                block(tool == .run ? "Result" : "Found", result.value)
            }
            if !result.console.isEmpty { block("Console", result.console) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(GlassInk.sunk(0.25), in: coreShape(Radius.control))
        .padding([.horizontal, .bottom], Space.s2)
        .textSelection(.enabled)
        .agentCopyMenu(summary)
    }

    private func block(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(palette.text2)
            FoldedOutput(text: text)
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: Space.s2) {
            switch status {
            case .running:
                Text("running").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                CoreWorkingBar(width: Space.s8)
            case .done, .failed:
                if let f = result.footer ?? durationMs.map({ "\(coreDecimal(Double($0) / 1000, 1)) s" }) {
                    Text(f).coreFont(size: MacTextSize.meta, design: .monospaced).foregroundStyle(palette.text2)
                        .monospacedDigit().lineLimit(1).fixedSize()
                }
                Image(systemName: status == .done ? "checkmark" : "xmark")
                    .coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(status == .done ? palette.primary : palette.tone(.fail).ink)
                    .accessibilityLabel(status == .done ? "Done" : "Refused")
            }
        }
    }
}
