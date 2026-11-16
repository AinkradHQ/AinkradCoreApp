import CoreUI
import SwiftUI

/// A sub-agent the session started (the Task / Agent tool). Its details live in the side panel (direction A, approved
/// 2026-11-16); the conversation keeps one quiet line where it started, like a tool step.
struct SubAgentInfo: Identifiable, Equatable {
    let id: String
    let type: String
    let task: String
    let prompt: String
    let result: String?
    let ok: Bool?
    let ms: Int?

    var state: (word: String, tone: Tone) {
        switch ok {
        case nil: ("Working", .run)
        case true?: ("Done", .done)
        case false?: ("Failed", .fail)
        }
    }

    /// Its kind as words: "general-purpose" reads "General purpose".
    static func kind(_ type: String) -> String {
        let s = type.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// The session's sub-agents, in the order they started.
    static func all(_ entries: [TranscriptEntry]) -> [SubAgentInfo] {
        entries.compactMap {
            guard case .subAgent(let id, let type, let task, let prompt, let result, let ok, let ms) = $0.kind else {
                return nil
            }
            return SubAgentInfo(id: id, type: type, task: task, prompt: prompt, result: result, ok: ok, ms: ms)
        }
    }
}

/// The transcript's line for a sub-agent: "Started a sub-agent · Find where queue limits are enforced · Explore", its state
/// at the end. The report is in the side panel's Sub-agents section.
struct SubAgentLine: View {
    let info: SubAgentInfo
    /// When it started: a working one counts up ("Working · 1:12").
    var since = Date()
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Image(systemName: "person.2").coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2)
                .frame(width: Space.s4)
            Text("Sub-agent").coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text2)
            Text(info.task).coreFont(size: MacTextSize.body).foregroundStyle(SessionInk.text).lineLimit(1)
            Text(SubAgentInfo.kind(info.type)).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
            if info.ok == nil {
                CoreWorkingBar(width: Space.s8)
                TimelineView(.periodic(from: since, by: 1)) { ctx in
                    Text("Working · " + AgentWords.clock(max(0, ctx.date.timeIntervalSince(since))))
                        .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2).monospacedDigit()
                }
            } else {
                Label(info.state.word, systemImage: info.ok == true ? "checkmark" : "xmark")
                    .coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(info.ok == true ? palette.primary : SessionInk.bad)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2).frame(minHeight: 28)
        .help("\(info.task)\nIts report is in the side panel, under Sub-agents.")
        .accessibilityElement(children: .combine)
    }
}

/// The side panel's Sub-agents list: each one's job, kind, time and state; a click shows its report (or its brief while
/// it works).
struct SubAgentsList: View {
    let list: [SubAgentInfo]
    @State private var open: String?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(list) { a in
                Button {
                    withAnimation(Motion.calm(Motion.out(Motion.ui), reduce)) { open = open == a.id ? nil : a.id }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.task).coreFont(size: MacTextSize.body).lineLimit(1).truncationMode(.tail)
                            Text(
                                [SubAgentInfo.kind(a.type), a.ms.map { "\(coreDecimal(Double($0) / 1000, 1)) s" }]
                                    .compactMap { $0 }
                                    .joined(separator: " · ")
                            )
                            .coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text2)
                        }
                        Spacer(minLength: Space.s2)
                        Text(a.state.word).coreFont(size: MacTextSize.meta)
                            .foregroundStyle(a.ok == false ? SessionInk.bad : SessionInk.text2)
                    }
                    .padding(.vertical, Space.s1).contentShape(Rectangle())
                }
                .buttonStyle(CoreQuietPressStyle(radius: Radius.control, scale: 0.99, hoverFill: true))
                .help(open == a.id ? "Hide its report" : "Show its report")
                if open == a.id {
                    Text(a.result ?? a.prompt).coreFont(size: MacTextSize.meta).foregroundStyle(SessionInk.text)
                        .textSelection(.enabled).lineLimit(14)
                        .padding(Space.s2).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SessionInk.code, in: coreShape(Radius.control))
                        .transition(.opacity)
                }
            }
        }
    }
}
