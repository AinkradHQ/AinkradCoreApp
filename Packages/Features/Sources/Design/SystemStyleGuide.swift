import CoreUI
import SwiftUI

/// A design system, opened: a live style guide. Colours, type, spacing, radii and shadows rendered from the system's own
/// tokens, then a few components built from them. Click any token to edit it in place (day and night); designs that use
/// the system follow. An empty system starts from a calm default set or from AI with a brand kit (Core API 108). The
/// system doc is open on a hidden canvas engine, which syncs it and takes the token edits (one undo step each).
struct SystemStyleGuide: View {
    let model: DesignModel
    let doc: DesignDoc
    @Bindable var editor: DesignEditor
    let canvas: AnyView
    @State private var night = false
    @State private var ai = SystemAI()
    @State private var asking = false
    @State private var adding = false
    /// The second press: a system that already has tokens asks before the AI replaces them.
    @State private var confirming = false
    @Environment(\.coreAccent) private var paneAccent

    private var tokens: [SystemToken] { editor.systemTokens }
    /// A group in design order (primary first, display to caption, xs to xl), unknown names after, by name.
    private func group(_ g: String) -> [SystemToken] {
        let order = [
            "primary", "secondary", "accent", "background", "surface", "text", "muted", "border", "success", "warning",
            "danger", "display", "title", "heading", "body", "caption", "xs", "sm", "md", "lg", "xl",
        ]
        return tokens.filter { $0.group == g }.sorted {
            (order.firstIndex(of: $0.short) ?? 99, $0.short) < (order.firstIndex(of: $1.short) ?? 99, $1.short)
        }
    }
    private func value(_ name: String) -> DJSON? { tokens.first { $0.name == name }.map { night ? $0.night : $0.day } }
    private func color(_ name: String, _ fallback: Color) -> Color {
        FrameSketch.color(value(name)?.string, fallback: fallback)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvas.frame(width: 1, height: 1).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            VStack(spacing: 0) {
                bar
                if tokens.isEmpty { empty } else { guide }
            }
        }
        .background(color("color.background", night ? Color(white: 0.08) : .white).opacity(tokens.isEmpty ? 0 : 1))
        .clipShape(coreShape(Radius.pane))
        .onChange(of: asking) { _, on in if !on { confirming = false } }
        .animation(Motion.out(Motion.ui), value: night)
        .animation(Motion.out(Motion.ui), value: tokens.count)
        .accessibilityIdentifier("design-system-guide")
        #if DEBUG
        .onAppear {
            if model.debugAddTokenOpen { adding = true }
            if model.debugSystemAsk {
                asking = true
                confirming = true
            }
        }
        #endif
    }

    // MARK: bar

    private var bar: some View {
        HStack(spacing: Space.s2) {
            Text("\(tokens.count) tokens").foregroundStyle(GlassInk.secondary).monospacedDigit()
            if ai.busy {
                ProgressView().controlSize(.small)
                Text(ai.progress ?? "AI is writing the system…").foregroundStyle(GlassInk.secondary).lineLimit(1)
                Button("Stop") { ai.stop(model: model) }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .help("Stop the AI and keep the tokens as they are")
            } else if let e = ai.error {
                Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(GlassInk.secondary).lineLimit(1)
                if ai.canRetry {
                    Button("Try again") { ai.start(model: model, doc: doc.id, kit: nil, resuming: true) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .help("Ask the Core about the same drawing first")
                }
            }
            Spacer(minLength: 0)
            CoreSegmented(
                "Theme",
                segments: [CoreSegment(false, "Day", symbol: "sun.max"), CoreSegment(true, "Night", symbol: "moon")],
                selection: $night)
            Button {
                adding = true
            } label: {
                Label("Add token", systemImage: "plus")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .disabled(!editor.attached || model.readOnly)
            .help(
                model.readOnly
                    ? "This device can look at designs but not change them."
                    : "Add a colour, type, spacing, radius or shadow token"
            )
            .popover(isPresented: $adding, arrowEdge: .bottom) { AddTokenSheet(editor: editor) { adding = false } }
            .accessibilityIdentifier("design-add-token-button")
            Button {
                asking = true
            } label: {
                Label("Generate with AI", systemImage: "sparkles")
            }
            .buttonStyle(CoreButtonStyle(.secondary))
            .disabled(!model.systemAISupported || ai.busy || model.readOnly)
            .help(
                model.systemAISupported
                    ? "Describe the brand; AI writes colours, type, spacing, radii and shadows"
                    : "Needs the next Core update"
            )
            .popover(isPresented: $asking, arrowEdge: .bottom) { askSheet }
        }
        .padding(.horizontal, Space.s4).frame(height: MacSize.controlLg + Space.s3)
        .background(GlassInk.adaptive(Color(white: 0.11), day: Color(white: 0.97)))
    }

    private var askSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Generate a design system").coreFont(size: MacTextSize.headline, weight: .semibold)
            CoreTextField("Describe the brand", placeholder: "A calm, trustworthy banking app", text: $ai.prompt) {
                run()
            }
            if !model.kits.isEmpty {
                CoreSelect(
                    "Brand kit", selection: $ai.kit,
                    options: [CoreSelectOption("", "None")]
                        + model.kits.filter { $0.kind == .brandKit }.map { CoreSelectOption($0.id, $0.name) })
            }
            if ai.overLimit {
                Text(
                    "That is \(ai.promptLength - DesignComposer.promptLimit) characters too long. Shorten it to generate."
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            if tokens.isEmpty {
                Text("It writes 26 tokens.").coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            } else if confirming {
                CoreNotice(
                    symbol: "exclamationmark.triangle",
                    title: "Replaces \(tokens.count) tokens: the colour, type, spacing, radius and shadow ones.",
                    tone: .warn)
            } else {
                Text("It replaces the colour, type, spacing, radius and shadow tokens.")
                    .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            HStack {
                Spacer()
                Button(confirming ? "Replace \(tokens.count) tokens" : "Generate") {
                    if tokens.isEmpty || confirming { run() } else { confirming = true }
                }
                .buttonStyle(CoreButtonStyle(.prominent)).coreShortcut(.primary)
                .disabled(ai.prompt.trimmingCharacters(in: .whitespaces).isEmpty || ai.overLimit)
                .help(ai.overLimit ? "The description is too long" : "")
            }
        }
        .padding(Space.s4).frame(width: Space.s8 * 12)
    }

    private func run() {
        asking = false
        confirming = false
        let kit = model.kits.first { $0.id == ai.kit }
        ai.start(model: model, doc: doc.id, kit: kit)
    }

    // MARK: empty

    private var empty: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "swatchpalette").coreFont(size: 40).foregroundStyle(GlassInk.secondary)
            Text("This design system is empty").coreFont(size: MacTextSize.title, weight: .semibold)
            Text("Start from a calm default set you can change, or describe the brand and let AI write it.")
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center).frame(maxWidth: Space.s8 * 14)
            HStack(spacing: Space.s2) {
                Button("Start from the default set") { editor.setTokens(SystemStarter.tokens) }
                    .buttonStyle(CoreButtonStyle(.secondary))
                    .disabled(!editor.attached || model.readOnly)
                Button {
                    asking = true
                } label: {
                    Label("Generate with AI", systemImage: "sparkles")
                }
                .buttonStyle(CoreButtonStyle(.prominent))
                .disabled(!model.systemAISupported || model.readOnly)
            }
            if !model.systemAISupported {
                Text("AI generation arrives with the next Core update.").coreFont(size: MacTextSize.meta)
                    .foregroundStyle(GlassInk.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: guide

    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s8) {
                section("Colours") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s3)], spacing: Space.s3) {
                        ForEach(group("color")) { t in TokenEditButton(editor: editor, token: t) { colorCard(t) } }
                    }
                }
                section("Type") {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(group("type")) { t in TokenEditButton(editor: editor, token: t) { typeRow(t) } }
                    }
                }
                HStack(alignment: .top, spacing: Space.s8) {
                    section("Spacing") {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            ForEach(group("space")) { t in TokenEditButton(editor: editor, token: t) { spaceRow(t) } }
                        }
                    }
                    section("Radius") {
                        HStack(spacing: Space.s3) {
                            ForEach(group("radius")) { t in TokenEditButton(editor: editor, token: t) { radiusTile(t) }
                            }
                        }
                    }
                    section("Shadow") {
                        HStack(spacing: Space.s4) {
                            ForEach(group("shadow")) { t in TokenEditButton(editor: editor, token: t) { shadowTile(t) }
                            }
                        }
                    }
                }
                section("Components") { SystemComponents(value: value) }
            }
            .padding(Space.s6)
        }
        .scrollIndicators(.never)
        .foregroundStyle(color("color.text", night ? .white : .black))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var muted: Color { color("color.muted", .gray) }

    private func colorCard(_ t: SystemToken) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 0) {
                FrameSketch.color(t.day.string, fallback: .gray)
                FrameSketch.color(t.night.string, fallback: .gray)
            }
            .frame(height: 64).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(muted.opacity(0.25)))
            Text(t.short).coreFont(size: MacTextSize.body, weight: .semibold)
            Text("\((t.day.string ?? "").uppercased()) · \((t.night.string ?? "").uppercased())")
                .coreFont(size: MacTextSize.meta).foregroundStyle(muted).monospaced()
        }
    }

    private func typeRow(_ t: SystemToken) -> some View {
        let v = night ? t.night : t.day
        let size = v["size"]?.double ?? 16
        let weight = v["weight"]?.double ?? 400
        return HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Text(t.short).coreFont(size: MacTextSize.meta).foregroundStyle(muted).frame(width: 80, alignment: .leading)
            Text("The quick brown fox").font(.system(size: min(size, 72), weight: Font.Weight(weight: weight)))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(Int(size)) / \(Int(weight))" + (v["line"]?.double.map { " / \(Int($0))" } ?? ""))
                .coreFont(size: MacTextSize.meta).foregroundStyle(muted).monospacedDigit()
        }
    }

    private func spaceRow(_ t: SystemToken) -> some View {
        let n = (night ? t.night : t.day).double ?? 0
        return HStack(spacing: Space.s3) {
            Text(t.short).coreFont(size: MacTextSize.meta).foregroundStyle(muted).frame(width: 32, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(color("color.primary", .blue).opacity(0.7))
                .frame(width: max(2, min(n * 3, 240)), height: 14)
            Text("\(Int(n))").coreFont(size: MacTextSize.meta).foregroundStyle(muted).monospacedDigit()
        }
    }

    private func radiusTile(_ t: SystemToken) -> some View {
        let n = (night ? t.night : t.day).double ?? 0
        return VStack(spacing: Space.s1) {
            RoundedRectangle(cornerRadius: min(n, 32), style: .continuous).fill(
                color("color.surface", .gray.opacity(0.2))
            )
            .overlay(RoundedRectangle(cornerRadius: min(n, 32), style: .continuous).strokeBorder(muted.opacity(0.4)))
            .frame(width: 64, height: 64)
            Text("\(t.short) · \(Int(n))").coreFont(size: MacTextSize.meta).foregroundStyle(muted)
        }
    }

    private func shadowTile(_ t: SystemToken) -> some View {
        let s = (night ? t.night : t.day).array?.first
        return VStack(spacing: Space.s1) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color("color.surface", .white))
                .frame(width: 80, height: 64)
                .shadow(
                    color: FrameSketch.color(s?["color"]?.string, fallback: .black.opacity(0.2)),
                    radius: (s?["blur"]?.double ?? 8) / 2, x: s?["x"]?.double ?? 0, y: s?["y"]?.double ?? 4)
            Text(t.short).coreFont(size: MacTextSize.meta).foregroundStyle(muted)
        }
        .padding(Space.s2)
    }
}

/// A token's tile: a click opens its editor (day and night).
private struct TokenEditButton<Label: View>: View {
    let editor: DesignEditor
    let token: SystemToken
    @ViewBuilder let label: Label
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button {
            open = true
        } label: {
            label.padding(Space.s2)
                .background(hovering ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
                .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Edit \(token.name)")
        .popover(isPresented: $open, arrowEdge: .bottom) { TokenEditor(editor: editor, token: token) }
    }
}
