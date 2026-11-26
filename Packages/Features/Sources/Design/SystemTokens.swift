import CoreUI
import Observation
import SwiftUI

/// The style guide's parts: a token's editor, the components preview, the default set and the AI run.

/// One token's editor (a popover): day and night values for its kind, Remove.
struct TokenEditor: View {
    let editor: DesignEditor
    let token: SystemToken

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(token.name).coreFont(size: MacTextSize.headline, weight: .semibold).monospaced()
                Spacer()
                Button("Remove", role: .destructive) {
                    editor.setToken(token.name, kind: token.kind, day: nil, night: nil)
                }
                .buttonStyle(.coreQuietDanger)
            }
            row("Day", token.day) { set(day: $0) }
            row("Night", token.night) { set(night: $0) }
        }
        .padding(Space.s4).frame(width: Space.s8 * 11)
    }

    private func set(day: DJSON? = nil, night: DJSON? = nil) {
        editor.setToken(token.name, kind: token.kind, day: day ?? token.day, night: night ?? token.night)
    }

    @ViewBuilder private func row(_ title: String, _ v: DJSON, _ put: @escaping (DJSON) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(GlassInk.secondary)
            switch token.kind {
            case "color":
                ColorField(hex: v.string) { put(.string($0)) }
            case "space", "size", "radius":
                InlineNumber(label: "pt", value: v.double) { put(.number(max(0, $0 ?? 0))) }
            case "type":
                HStack(spacing: Space.s1) {
                    InlineNumber(label: "Size", value: v["size"]?.double) {
                        put(Self.merge(v, "size", .number(max(1, $0 ?? 16))))
                    }
                    InlineNumber(label: "Weight", value: v["weight"]?.double) {
                        put(Self.merge(v, "weight", .number(min(1000, max(1, ($0 ?? 400).rounded())))))
                    }
                    InlineNumber(label: "Line", value: v["line"]?.double, clearable: true) {
                        put(Self.merge(v, "line", $0.map { .number(max(0, $0)) }))
                    }
                }
            case "shadow":
                let s = v.array?.first ?? .object([:])
                HStack(spacing: Space.s1) {
                    InlineNumber(label: "Y", value: s["y"]?.double) {
                        put(.array([Self.merge(s, "y", .number($0 ?? 0))]))
                    }
                    InlineNumber(label: "Blur", value: s["blur"]?.double) {
                        put(.array([Self.merge(s, "blur", .number(max(0, $0 ?? 0)))]))
                    }
                }
                ColorField(hex: s["color"]?.string) { put(.array([Self.merge(s, "color", .string($0))])) }
            default:
                Text(String(describing: v)).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
    }

    static func merge(_ v: DJSON, _ key: String, _ new: DJSON?) -> DJSON {
        var o = v.object ?? [:]
        o[key] = new
        return .object(o)
    }
}

/// A few components made from the system's tokens, so a change shows where it lands.
struct SystemComponents: View {
    let value: (String) -> DJSON?

    private func c(_ n: String, _ f: Color) -> Color { FrameSketch.color(value(n)?.string, fallback: f) }
    private func r(_ n: String, _ f: Double) -> CGFloat { CGFloat(value(n)?.double ?? f) }
    private func font(_ n: String, _ size: Double, _ weight: Double) -> Font {
        let v = value(n)
        return .system(
            size: min(v?["size"]?.double ?? size, 64), weight: Font.Weight(weight: v?["weight"]?.double ?? weight))
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s6) {
            VStack(alignment: .leading, spacing: r("space.md", 16)) {
                Text("Welcome back").font(font("type.title", 28, 700)).foregroundStyle(c("color.text", .primary))
                Text("Sign in to keep going where you left off.").font(font("type.body", 16, 400))
                    .foregroundStyle(c("color.muted", .secondary))
                Text("you@example.com").font(font("type.body", 16, 400)).foregroundStyle(c("color.muted", .secondary))
                    .padding(.horizontal, r("space.md", 16)).frame(
                        maxWidth: .infinity, minHeight: 44, alignment: .leading
                    )
                    .background(c("color.surface", .white), in: RoundedRectangle(cornerRadius: r("radius.md", 8)))
                    .overlay(RoundedRectangle(cornerRadius: r("radius.md", 8)).strokeBorder(c("color.border", .gray)))
                HStack(spacing: r("space.sm", 8)) {
                    Text("Sign in").font(font("type.body", 16, 600)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(c("color.primary", .blue), in: RoundedRectangle(cornerRadius: r("radius.md", 8)))
                    Text("Create account").font(font("type.body", 16, 600)).foregroundStyle(c("color.primary", .blue))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: r("radius.md", 8)).strokeBorder(c("color.primary", .blue)))
                }
            }
            .padding(r("space.lg", 24))
            .frame(width: 360)
            .background(c("color.surface", .white), in: RoundedRectangle(cornerRadius: r("radius.lg", 16)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: r("space.sm", 8)) {
                ForEach(
                    [
                        ("Saved", "color.success"), ("Check the details", "color.warning"),
                        ("Payment failed", "color.danger"),
                    ], id: \.0
                ) { t, k in
                    Text(t).font(font("type.caption", 13, 500)).foregroundStyle(c(k, .gray))
                        .padding(.horizontal, r("space.sm", 8)).padding(.vertical, 4)
                        .background(c(k, .gray).opacity(0.14), in: RoundedRectangle(cornerRadius: r("radius.sm", 4)))
                }
                Text("Featured").font(font("type.caption", 13, 600)).foregroundStyle(.white)
                    .padding(.horizontal, r("space.sm", 8)).padding(.vertical, 4)
                    .background(c("color.accent", .orange), in: RoundedRectangle(cornerRadius: r("radius.sm", 4)))
            }
        }
    }
}

/// A calm default system, the same names the Core's AI writes: 11 colours, 5 type styles, 5 spaces, 3 radii, 2 shadows.
enum SystemStarter {
    static func color(_ n: String, _ d: String, _ night: String) -> SystemToken {
        SystemToken(name: "color.\(n)", kind: "color", day: .string(d), night: .string(night))
    }
    static func type(_ n: String, _ size: Double, _ weight: Double, _ line: Double) -> SystemToken {
        let v: DJSON = .object(["size": .number(size), "weight": .number(weight), "line": .number(line)])
        return SystemToken(name: "type.\(n)", kind: "type", day: v, night: v)
    }
    static func num(_ group: String, _ n: String, _ v: Double) -> SystemToken {
        SystemToken(
            name: "\(group).\(n)", kind: group == "space" ? "space" : "radius", day: .number(v), night: .number(v))
    }
    static func shadow(_ n: String, _ y: Double, _ blur: Double, _ a: String) -> SystemToken {
        let v: DJSON = .array([
            .object([
                "x": .number(0), "y": .number(y), "blur": .number(blur), "spread": .number(0),
                "color": .string("#000000\(a)"),
            ])
        ])
        return SystemToken(name: "shadow.\(n)", kind: "shadow", day: v, night: v)
    }

    static let tokens: [SystemToken] = [
        color("primary", "#2f6fec", "#5b8ff5"), color("secondary", "#5c6b80", "#9aa7b8"),
        color("accent", "#e8a33d", "#f0b65c"), color("background", "#f6f7f9", "#0f1115"),
        color("surface", "#ffffff", "#181b21"), color("text", "#14171c", "#eef1f5"),
        color("muted", "#6a7380", "#9aa3ae"), color("border", "#dde1e6", "#2a2f38"),
        color("success", "#1f9d61", "#3cc483"), color("warning", "#c98411", "#e8a83a"),
        color("danger", "#d23c3c", "#f06666"),
        type("display", 44, 700, 52), type("title", 28, 700, 34), type("heading", 20, 600, 26),
        type("body", 16, 400, 24), type("caption", 13, 500, 18),
        num("space", "xs", 4), num("space", "sm", 8), num("space", "md", 16), num("space", "lg", 24),
        num("space", "xl", 40),
        num("radius", "sm", 4), num("radius", "md", 8), num("radius", "lg", 16),
        shadow("sm", 1, 3, "1f"), shadow("md", 6, 18, "29"),
    ]
}

/// A brand-kit colour as the Core takes it: `#rrggbb`. `#rgb` is expanded, an alpha channel dropped, anything else is out.
enum BrandColor {
    static func normalize(_ raw: String) -> String? {
        var h = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.allSatisfy(\.isHexDigit), h.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        switch h.count {
        case 3, 4: return "#" + h.prefix(3).map { "\($0)\($0)" }.joined()
        case 6, 8: return "#" + h.prefix(6)
        default: return nil
        }
    }
}

/// The AI run that writes a whole system (`compose` with `mode: "system"`): start, then poll until the Core is done.
/// It can be stopped (the Core session too), and after a failed poll "Try again" asks the Core about the same run first.
@MainActor @Observable
final class SystemAI {
    var prompt = ""
    var kit = ""
    private(set) var busy = false
    private(set) var error: String?
    /// What the Core says it is doing, and how far (optional fields of the state).
    private(set) var progress: String?
    private(set) var canRetry = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var last: ComposeState?
    @ObservationIgnored private var runID = 0

    var promptLength: Int { prompt.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count }
    var overLimit: Bool { promptLength > DesignComposer.promptLimit }

    func start(model: DesignModel, doc: String, kit: BrandKit?, resuming: Bool = false) {
        guard !busy, let service = model.service else { return }
        busy = true
        error = nil
        progress = nil
        canRetry = false
        runID += 1
        let run = runID
        let text = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.prefix(1000))
        let colors = Array(Set((kit?.colors ?? []).compactMap(BrandColor.normalize))).sorted()
        let name = kit?.name
        let resume = resuming ? last : nil
        last = nil
        task = Task { [weak self] in
            do {
                let s = try await ComposePoll.run(
                    service: service, doc: doc, resume: resume,
                    start: { try await service.composeSystem(doc: doc, prompt: text, brandName: name, colors: colors) },
                    onState: { s in
                        guard let self, self.runID == run else { return }
                        self.last = s
                        self.progress = Self.words(s)
                    })
                guard let self, self.runID == run else { return }
                self.busy = false
                self.last = nil
                if s.phase != .done { self.error = s.reason.isEmpty ? "The AI could not write this system." : s.reason }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.runID == run else { return }
                self.busy = false
                self.canRetry = !(error is ComposeTimedOut) && self.last != nil
                self.error = error is ComposeTimedOut ? "The AI took too long. Try again." : model.words(error)
            }
        }
    }

    /// Stops the run and the Core's session.
    func stop(model: DesignModel) {
        runID += 1
        task?.cancel()
        if let id = last?.session, let service = model.service {
            Task { try? await service.cancelCompose(session: id) }
        }
        last = nil
        busy = false
        progress = nil
    }

    private static func words(_ s: ComposeState) -> String? {
        var parts: [String] = []
        if let stage = s.stage, !stage.isEmpty { parts.append(stage) }
        if let d = s.elementsDone, let t = s.elementsTotal, t > 0 { parts.append("\(d) of \(t)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
