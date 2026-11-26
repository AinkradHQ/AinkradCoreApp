import CoreUI
import SwiftUI

/// The AI panel over the canvas (not a dialog: the canvas stays in sight and usable). Prompt → drawing → result:
/// - Prompt: New screen or Edit the selected frame, One design or Three ideas for a new one, a few starting words, Return.
/// - Drawing: a glow runs round the panel, the stages say what the AI is doing, the screens it will place shimmer.
/// - Result: the directions rise in with their pictures (a click shows one on the canvas, Use this keeps it), or for an
///   edit and a one-design drawing the change is already on the canvas with Undo.
/// Reduce Motion keeps every state and drops the movement.
struct DesignAIPanel: View {
    @Bindable var composer: DesignComposer
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreAccent) private var paneAccent
    @FocusState private var field: Bool

    private var ink: Color { GlassInk.accent(paneAccent) }
    private var drawing: Bool { composer.phase == .drawing }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            Group {
                switch composer.phase {
                case .prompt: prompt
                case .drawing: progress
                case .directions: directions
                case .done(let words): done(words)
                case .failed(let why): failed(why)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 20)
        .background(GlassInk.adaptive(Color(white: 0.13), day: .white), in: coreShape(Radius.cardMac + 4))
        .overlay { AIGlow(running: drawing && !reduce, ink: ink).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .animation(Motion.out(Motion.ui), value: composer.phase)
        .onExitCommand { if drawing { composer.stop() } else { composer.close() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-ai-panel")
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "sparkles").coreFont(size: MacTextSize.headline, weight: .semibold)
                .foregroundStyle(ink)
                .symbolEffect(.pulse, options: .repeating, isActive: drawing && !reduce)
                .accessibilityHidden(true)
            Text(title).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            CoreIconButton(symbol: "xmark", label: drawing ? "Stop and close  Esc" : "Close  Esc") {
                if drawing { composer.stop() }
                composer.close()
            }
        }
    }

    private var title: String {
        switch composer.phase {
        case .prompt: composer.target.map { "Edit \($0.name) with AI" } ?? "Draw with AI"
        case .drawing: composer.editing ? "Redrawing \(composer.target?.name ?? "the screen")…" : "Drawing…"
        case .directions: "Pick a direction"
        case .done: "Done"
        case .failed: "That did not work"
        }
    }

    // MARK: prompt

    private var prompt: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                if let t = composer.target {
                    modeChip("Edit \(t.name)", "wand.and.stars", on: true) {}
                    modeChip("New screen", "plus.rectangle", on: false) { composer.target = nil }
                } else {
                    modeChip("One design", "rectangle", on: composer.single) { composer.single = true }
                    modeChip("Three ideas", "rectangle.split.3x1", on: !composer.single) { composer.single = false }
                }
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                TextField(
                    "", text: $composer.prompt,
                    prompt: Text(
                        composer.editing
                            ? "What should change? e.g. make the button green"
                            : "Describe the screen, e.g. a calm sign-in"
                    ).foregroundStyle(GlassInk.secondary), axis: .vertical
                )
                .textFieldStyle(.plain).lineLimit(1...4).focused($field)
                .onSubmit { composer.draw() }
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .frame(minHeight: MacSize.controlLg + Space.s1)
                .coreFieldSurface(focused: field)
                .accessibilityLabel(composer.editing ? "The change" : "The screen to draw")
                Button {
                    composer.draw()
                } label: {
                    Image(systemName: "arrow.up").coreFont(size: MacTextSize.body, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: MacSize.controlLg + Space.s1, height: MacSize.controlLg + Space.s1)
                        .background(
                            composer.canDraw ? ink : GlassInk.secondary.opacity(0.35), in: coreShape(Radius.control))
                }
                .buttonStyle(.plain)
                .disabled(!composer.canDraw)
                .help(composer.editing ? "Redraw it with the change  Return" : "Draw  Return")
                .accessibilityLabel("Draw")
            }
            suggestions
        }
        .onAppear { field = true }
    }

    private func modeChip(_ title: String, _ symbol: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            Label(title, systemImage: symbol).lineLimit(1)
                .coreFont(size: MacTextSize.meta, weight: on ? .semibold : .regular)
                .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
                .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
                .background(on ? ink.opacity(0.22) : GlassInk.well, in: coreShape(Radius.control))
                .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .animation(Motion.out(Motion.hover), value: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Starting words: a click puts them in the field.
    private var suggestions: some View {
        let words =
            composer.editing
            ? ["Make it darker", "Bigger headline", "Add a sign-in button", "More space between items"]
            : ["A calm sign-in screen", "A pricing page", "An onboarding step", "A settings screen"]
        return HStack(spacing: Space.s1) {
            ForEach(words, id: \.self) { w in
                Button {
                    composer.prompt = w
                    field = true
                } label: {
                    Text(w).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                        .padding(.horizontal, Space.s2).frame(height: MacSize.chip + 2)
                        .background(GlassInk.well, in: coreShape(Radius.chip))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: drawing

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let seconds = Int(ctx.date.timeIntervalSince(composer.startedAt ?? ctx.date))
                HStack(spacing: Space.s2) {
                    Text(AIStages.line(seconds: seconds, editing: composer.editing))
                        .foregroundStyle(GlassInk.secondary)
                        .id(AIStages.line(seconds: seconds, editing: composer.editing))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    Spacer(minLength: 0)
                    Text("\(seconds) s").monospacedDigit().coreFont(size: MacTextSize.meta)
                        .foregroundStyle(GlassInk.secondary).contentTransition(.numericText())
                }
                .animation(Motion.out(Motion.ui), value: seconds / 4)
            }
            HStack(spacing: Space.s3) {
                ForEach(0..<composer.expected, id: \.self) { i in
                    ShimmerScreen(delay: Double(i) * 0.25, running: !reduce, ink: ink)
                        .frame(maxWidth: .infinity).frame(height: Space.s8 * 5)
                }
            }
            HStack {
                Text("“\(composer.trimmed)”").foregroundStyle(GlassInk.secondary).lineLimit(1)
                Spacer(minLength: Space.s2)
                Button("Stop") { composer.stop() }.buttonStyle(CoreButtonStyle(.secondary))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The AI is drawing")
    }

    // MARK: result

    private var directions: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("They are on the canvas. Click one to look at it there; Use this keeps it and clears the others.")
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Space.s3) {
                ForEach(Array((composer.state?.directions ?? []).enumerated()), id: \.offset) { i, d in
                    DirectionCard(composer: composer, direction: d, best: i == 0, index: i, ink: ink)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                Button {
                    composer.again()
                } label: {
                    Label("Draw 3 more", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CoreButtonStyle(.secondary))
                Spacer(minLength: Space.s2)
                Button("Keep all three") { composer.close() }.buttonStyle(CoreButtonStyle(.secondary))
            }
        }
    }

    private func done(_ words: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.circle.fill").coreFont(size: MacTextSize.title).foregroundStyle(GlassInk.green)
                .symbolEffect(.bounce, value: words)
                .accessibilityHidden(true)
            Text(words).lineLimit(2)
            Spacer(minLength: Space.s2)
            Button("Undo") { composer.undo() }.buttonStyle(CoreButtonStyle(.secondary))
                .help("Put the canvas back as it was  ⌘Z")
            Button(composer.editing ? "Another change" : "Draw another") { composer.another() }
                .buttonStyle(CoreButtonStyle(.prominent))
        }
    }

    private func failed(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            CoreNotice(symbol: "exclamationmark.triangle", title: why, tone: .warn)
            HStack(spacing: Space.s2) {
                Spacer(minLength: Space.s2)
                Button("Change the words") { composer.another() }.buttonStyle(CoreButtonStyle(.secondary))
                Button("Try again") { composer.again() }.buttonStyle(CoreButtonStyle(.prominent))
            }
        }
    }
}

/// One direction: its picture (shimmering until the canvas has the frame), its name and words, Use this.
private struct DirectionCard: View {
    let composer: DesignComposer
    let direction: ComposeState.Direction
    let best: Bool
    let index: Int
    let ink: Color
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let sketch = composer.sketch(direction)
        VStack(alignment: .leading, spacing: Space.s2) {
            Group {
                if let sketch {
                    FrameSketchView(sketch: sketch).transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ShimmerScreen(delay: Double(index) * 0.2, running: !reduce, ink: ink)
                }
            }
            .frame(maxWidth: .infinity).frame(height: Space.s8 * 6)
            .animation(Motion.out(Motion.ui), value: sketch != nil)
            HStack(spacing: Space.s1) {
                Text(direction.name).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                if best { StateBadge("Best match", tone: .run, symbol: "star") }
            }
            Text(direction.summary).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: Space.s1) {
                Button("Use this") { composer.use(direction) }
                    .buttonStyle(CoreButtonStyle(best || hovering ? .prominent : .secondary, size: .small))
                Button("Refine") { composer.refine(direction) }.buttonStyle(CoreButtonStyle(.plain, size: .small))
            }
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(hovering ? GlassInk.wellHover : GlassInk.well, in: coreShape(Radius.pane))
        .contentShape(coreShape(Radius.pane))
        .onTapGesture { composer.preview(direction) }
        .onHover { hovering = $0 }
        .scaleEffect(hovering && !reduce ? 1.015 : 1)
        // Rise in one after another.
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduce ? 0 : 12)
        .onAppear {
            withAnimation(Motion.out(Motion.ui).delay(reduce ? 0 : Double(index) * 0.08)) { shown = true }
        }
        .animation(Motion.out(Motion.hover), value: hovering)
        .help("Click to see it on the canvas")
    }
}

/// What the panel says while the AI works, a new line every few seconds.
enum AIStages {
    static func line(seconds: Int, editing: Bool) -> String {
        let lines =
            editing
            ? [
                "Reading the screen…", "Working out the change…", "Redrawing the layout…", "Fitting the colours…",
                "Putting it back on the canvas…",
            ]
            : [
                "Reading your words…", "Sketching the layout…", "Choosing type and colours…", "Laying out the parts…",
                "Placing it on the canvas…",
            ]
        return lines[min(seconds / 4, lines.count - 1)]
    }
}

/// A phone-shaped placeholder with a light sweeping across it while the AI draws.
struct ShimmerScreen: View {
    var delay: Double = 0
    var running = true
    var ink: Color

    var body: some View {
        TimelineView(.animation(paused: !running)) { ctx in
            let t =
                running
                ? (ctx.date.timeIntervalSinceReferenceDate + delay).truncatingRemainder(dividingBy: 1.6) / 1.6 : 0.5
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    coreShape(Radius.cardMac).fill(GlassInk.well)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        coreShape(4).fill(ink.opacity(0.25)).frame(height: Space.s5)
                        ForEach(0..<4, id: \.self) { i in
                            coreShape(3).fill(GlassInk.secondary.opacity(0.16))
                                .frame(width: g.size.width * (i.isMultiple(of: 2) ? 0.7 : 0.5), height: Space.s2)
                        }
                        Spacer(minLength: 0)
                        coreShape(4).fill(ink.opacity(0.3)).frame(height: Space.s4)
                    }
                    .padding(Space.s3)
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.14), .clear], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: g.size.width * 0.6)
                    .offset(x: -g.size.width * 0.6 + (g.size.width * 1.6) * t)
                    .blendMode(.plusLighter)
                }
                .clipShape(coreShape(Radius.cardMac))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The glow that runs round the panel while the AI works: an accent arc travelling along the rim.
struct AIGlow: View {
    let running: Bool
    let ink: Color

    var body: some View {
        TimelineView(.animation(paused: !running)) { ctx in
            let angle =
                running ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360 : 0
            coreShape(Radius.cardMac + 4)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            ink.opacity(0), ink.opacity(0.9), .white.opacity(0.7), ink.opacity(0.9), ink.opacity(0),
                        ],
                        center: .center, angle: .degrees(angle)),
                    lineWidth: 1.5
                )
                .opacity(running ? 1 : 0)
                .animation(Motion.out(Motion.ui), value: running)
        }
    }
}
