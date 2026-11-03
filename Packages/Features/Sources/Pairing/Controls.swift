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

/// A one-line text field in a rounded-rect well, with its label above and an error below.
struct FieldBox: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var error: String?
    var mono = false
    var autofocus = false
    var onSubmit: () -> Void = {}
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).font(.system(size: MacTextSize.meta, weight: .semibold)).foregroundStyle(palette.text2)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(mono ? .system(size: MacTextSize.title, design: .monospaced) : .system(size: MacTextSize.body))
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(onSubmit)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: MacSize.controlLg)
                .background(palette.glassCard, in: coreShape(Radius.control))
                .overlay {
                    coreShape(Radius.control).strokeBorder(
                        error == nil ? palette.glassCardEdge : palette.tone(.fail).ink, lineWidth: 1)
                }
                .coreFocusRing(focused, radius: Radius.control, palette: palette)
                .accessibilityLabel(label)
                .onAppear { if autofocus { focused = true } }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.tone(.fail).ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The check code (SAS): four groups of four, in a rounded-rect well, read letter by letter.
struct SASView: View {
    let sas: String
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(Array(sas.split(separator: "-").enumerated()), id: \.offset) { _, group in
                Text(String(group)).font(.system(size: MacTextSize.large, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.glassCard, in: coreShape(Radius.control))
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

/// A scope as a checkbox with its plain meaning beside it.
struct ScopeToggle: View {
    let scope: String
    @Binding var on: Bool
    var locked: String?
    @Environment(\.corePalette) private var palette

    var body: some View {
        Toggle(isOn: $on) {
            VStack(alignment: .leading, spacing: 0) {
                Text(scope).font(.system(size: MacTextSize.body, weight: .semibold, design: .monospaced))
                Text(locked ?? ScopeText.text(scope)).font(.system(size: MacTextSize.meta))
                    .foregroundStyle(palette.text2)
            }
        }
        .toggleStyle(.checkbox)
        .tint(palette.primary)
        .disabled(locked != nil)
        .accessibilityLabel("\(scope), \(ScopeText.text(scope))")
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

/// A spinner for the dark glass panels: the panel is dark in both themes, so the spinner is too.
struct Spin: View {
    var body: some View { ProgressView().controlSize(.small).environment(\.colorScheme, .dark) }
}
