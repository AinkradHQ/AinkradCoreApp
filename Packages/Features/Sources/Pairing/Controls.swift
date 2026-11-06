import CoreUI
import SwiftUI

/// The check code (SAS): four large keycaps of four characters across the panel, read letter by letter.
struct SASView: View {
    let sas: String
    /// Groups the approver has typed correctly so far: each shows a tick, the next one a ring.
    var matched: Int?
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s3) {
            ForEach(Array(sas.split(separator: "-").enumerated()), id: \.offset) { i, group in
                Text(String(group))
                    .font(.system(size: MacTextSize.large * 1.5, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: MacSize.controlLg * 2)
                    .background(palette.glassCard, in: coreShape(Radius.cardMac))
                    .overlay {
                        coreShape(Radius.cardMac).strokeBorder(
                            ring(i) ? palette.primary : palette.glassCardEdge, lineWidth: ring(i) ? 2 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if let matched, i < matched {
                            Image(systemName: "checkmark.square.fill").foregroundStyle(palette.tone(.done).ink)
                                .padding(Space.s1)
                        }
                    }
            }
        }
        .animation(Motion.out(Motion.hover), value: matched)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Check code \(sas.replacingOccurrences(of: "-", with: " ").map { String($0) }.joined(separator: " "))"
        )
        .accessibilityIdentifier("sas")
    }
}

extension SASView {
    fileprivate func ring(_ i: Int) -> Bool { matched == i }
}

/// Label and value, one per line, for facts the Core told us.
struct FactRow: View {
    let key: String
    let value: String
    var mono = false
    @Environment(\.corePalette) private var palette
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(palette.text2)
            Spacer(minLength: Space.s3)
            Text(value).font(mono ? .system(size: MacTextSize.body, design: .monospaced) : nil)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.system(size: MacTextSize.body))
        .accessibilityElement(children: .combine)
    }
}

struct FactCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) { content }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.glassCard, in: coreShape(Radius.cardMac))
    }
}

/// A scope as a checkbox with its plain meaning beside it (a locked scope says why instead).
/// One scope to switch on or off: the same tappable scope tile everywhere (Add device, Edit access). A scope that cannot
/// be given stays dim and says why.
struct ScopeToggle: View {
    let scope: String
    @Binding var on: Bool
    var locked: String?
    /// Its number in the list: ⌘1… switches it.
    var index: Int?

    var body: some View {
        Button {
            on.toggle()
        } label: {
            ScopeTile(
                symbol: ScopeText.symbol(scope), name: ScopeText.name(scope), detail: locked ?? ScopeText.text(scope),
                hue: ScopeText.hue(scope), on: on)
        }
        .buttonStyle(.plain)
        .modifier(TileKey(index: index))
        .disabled(locked != nil)
        .help(scope)
        .accessibilityLabel("\(ScopeText.name(scope)), \(ScopeText.text(scope))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

enum ScopeText {
    static let all = ["read", "approve", "terminal", "agent", "admin"]
    /// Each scope's picture and colour, the same on every screen.
    static func symbol(_ s: String) -> String {
        switch s {
        case "read": "eye"
        case "approve": "checkmark.seal"
        case "terminal": "terminal"
        case "agent": "play.fill"
        case "admin": "key"
        case "runner": "server.rack"
        default: "questionmark"
        }
    }
    static func hue(_ s: String) -> Color {
        switch s {
        case "read": GlassInk.blue
        case "approve", "agent", "admin": GlassInk.blue
        case "terminal": GlassInk.slate
        default: GlassInk.slate
        }
    }
    /// The scope as a person would say it; the raw name goes in `.help`.
    static func name(_ s: String) -> String {
        switch s {
        case "read": "See everything"
        case "approve": "Approve"
        case "terminal": "Use terminals"
        case "agent": "Run agents"
        case "admin": "Admin"
        case "runner": "Run for the Core"
        default: s
        }
    }
    static func text(_ s: String) -> String {
        switch s {
        case "read": "See sessions, runners, events and settings"
        case "approve": "Decide agent tool approvals"
        case "terminal": "Open and use terminals"
        case "agent": "Start and steer agent sessions"
        case "admin": "Devices, secrets and settings"
        case "runner": "Only redeems secret leases"
        default: "A scope this app does not know"
        }
    }
}

/// Words for a device's fields, never the raw wire values.
enum DeviceWords {
    static func storage(_ s: String?) -> String {
        switch s {
        case "secure_enclave": "In a chip"
        case "software": "In a file"
        case .some(let o): o
        case nil: "Didn't say"
        }
    }
    static func kind(_ k: String) -> String {
        switch k {
        case "runner": "Runner"
        case "passkey": "Browser (passkey)"
        default: "Device"
        }
    }
    static func symbol(_ kind: String, _ platform: String?) -> String {
        if kind == "runner" { return "server.rack" }
        if kind == "passkey" { return "globe" }
        switch platform {
        case "ios": return "iphone"
        case "macos": return "desktopcomputer"
        default: return "laptopcomputer"
        }
    }
    static func platform(_ p: String?) -> String {
        switch p {
        case "macos": "macOS"
        case "ios": "iOS"
        case .some(let o): o
        case nil: "Unknown platform"
        }
    }
    static func seen(_ d: Date?) -> String {
        guard let d else { return "Never" }
        if Date().timeIntervalSince(d) < 90 { return "Just now" }
        return d.formatted(.relative(presentation: .named))
    }
}

/// Progress with no end in sight, as a rounded-rect bar with a segment that slides (the prototype's `.ind`). Never a circle.
/// With Reduce Motion the segment rests in the middle.
struct IndBar: View {
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        TimelineView(.animation(paused: reduce)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / (Motion.tick * 1.5)
            let phase = reduce ? 0.5 : t - t.rounded(.down)
            GeometryReader { geo in
                let seg = geo.size.width * 0.3
                ZStack(alignment: .leading) {
                    coreShape(Space.s1 / 2).fill(palette.track)
                    coreShape(Space.s1 / 2).fill(palette.primary).frame(width: seg)
                        .offset(x: (geo.size.width - seg) * phase)  // grid: ok progress motion, not layout
                }
                .clipShape(coreShape(Space.s1 / 2))
            }
        }
        .frame(height: Space.s1)
        .accessibilityHidden(true)
    }
}

/// The pairing code as ten boxes in two groups of five, with "n of 10" under it (the prototype's code step). One real text field
/// sits invisibly over the boxes, so typing, paste, selection and VoiceOver all work as for any field.
struct CodeBoxes: View {
    let label: String
    @Binding var text: String
    var error: String?
    var onSubmit: () -> Void = {}
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

    private var chars: [Character] { Array(text.filter { $0 != "-" }) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            CoreFieldLabel(label)
            ZStack {
                HStack(spacing: Space.s4) {
                    group(0..<5)
                    group(5..<10)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain).foregroundStyle(Color.clear).tint(Color.clear)
                    .autocorrectionDisabled().focused($focused).onSubmit(onSubmit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(label)
            }
            .frame(height: MacSize.controlLg + Space.s4)
            Group {
                if chars.count == 10 {
                    Label("10 of 10, ready", systemImage: "checkmark")
                        .foregroundStyle(palette.tone(.run).ink)
                } else {
                    Text("\(chars.count) of 10").foregroundStyle(palette.text2)
                }
            }
            .font(.system(size: MacTextSize.meta, design: .monospaced).monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityHidden(true)
            if let error { CoreFieldError(error) }
        }
        .onAppear { focused = true }
    }

    private func group(_ range: Range<Int>) -> some View {
        HStack(spacing: Space.s1) {
            ForEach(range, id: \.self) { i in
                let active = focused && i == min(chars.count, 9)
                Text(i < chars.count ? String(chars[i]) : "")
                    .font(.system(size: MacTextSize.large, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .coreFieldSurface(focused: active, error: error != nil)
            }
        }
        .accessibilityHidden(true)
    }
}

/// ⌘ + a tile's number, shown on the tile; none when it has no number.
struct TileKey: ViewModifier {
    let index: Int?
    func body(content: Content) -> some View {
        if let index, index < 9 {
            content.coreTileKey("⌘\(index + 1)", key: Character("\(index + 1)"))
        } else {
            content
        }
    }
}
