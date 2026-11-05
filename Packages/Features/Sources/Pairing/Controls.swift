import CoreUI
import SwiftUI

/// Panel for a dialog over the shell (add device, scopes, revoke, Touch ID).
struct DialogCard<Content: View>: View {
    let title: String
    var width: CGFloat = Space.s8 * 15
    @ViewBuilder let content: Content
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title).font(.system(size: MacTextSize.large, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content
        }
        .foregroundStyle(palette.text)
        .corePanel(radius: Radius.panel, padding: Space.s6)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The check code (SAS): four large keycaps of four characters across the panel, read letter by letter.
struct SASView: View {
    let sas: String
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s3) {
            ForEach(Array(sas.split(separator: "-").enumerated()), id: \.offset) { _, group in
                Text(String(group))
                    .font(.system(size: MacTextSize.large * 1.6, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: MacSize.controlLg * 2)
                    .background(palette.glassCard, in: coreShape(Radius.cardMac))
                    .overlay { coreShape(Radius.cardMac).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Check code \(sas.replacingOccurrences(of: "-", with: " ").map { String($0) }.joined(separator: " "))"
        )
        .accessibilityIdentifier("sas")
    }
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
struct ScopeToggle: View {
    let scope: String
    @Binding var on: Bool
    var locked: String?

    var body: some View {
        CoreCheckbox(
            scope, detail: locked ?? ScopeText.text(scope), isOn: $on, mono: true,
            spoken: "\(scope), \(ScopeText.text(scope))"
        )
        .disabled(locked != nil)
    }
}

enum ScopeText {
    static let all = ["read", "approve", "terminal", "agent", "admin"]
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
        case "secure_enclave": "Secure Enclave (claimed)"
        case "software": "Software key (claimed)"
        case .some(let o): "\(o) (claimed)"
        case nil: "Not reported"
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

/// A destructive-leaning secondary button: the fail tone on a quiet fill. Used for "It doesn't match" and revoke.
struct DangerButtonStyle: ButtonStyle {
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let t = palette.tone(.fail)
        configuration.label
            .font(.system(size: MacTextSize.body, weight: .medium))
            .foregroundStyle(t.ink)
            .frame(minHeight: MacSize.controlMd)
            .padding(.horizontal, Space.s3)
            .background(configuration.isPressed ? t.fill.opacity(2) : t.fill, in: coreShape(Radius.control))
            .overlay { coreShape(Radius.control).strokeBorder(t.ink.opacity(0.5), lineWidth: 1) }
            .coreDimWhenDisabled(enabled)
    }
}

/// A text link in the primary colour, with the one focus ring (never the system accent's).
struct LinkButton: View {
    let title: String
    var hint: String?
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.plain).foregroundStyle(palette.primary)
            .focused($focused).focusEffectDisabled()
            .coreFocusRing(focused, radius: Radius.chip, palette: palette)
            .accessibilityHint(hint ?? "")
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
                    .coreGlassField(fallback: palette.glassCard)
                    .overlay {
                        coreShape(Radius.control).strokeBorder(
                            active ? palette.primary : error != nil ? palette.tone(.fail).ink : palette.glassCardEdge,
                            lineWidth: active ? 2 : 1)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
