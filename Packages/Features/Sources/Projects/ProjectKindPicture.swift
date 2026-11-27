import CoreUI
import SwiftUI

/// A small picture of what each kind of project is: a page, an app being built, services, documents. It loops slowly on the
/// empty gallery's tiles (`animated`) and stands still on a card's thumbnail. Plain rounded shapes on the pane's wells; under
/// Reduce Motion nothing moves and the one part that would have moved breathes in opacity instead.
struct KindPicture: View {
    let kind: ProjectKind
    let hue: Color
    var animated = true
    /// The picture is drawn on a 200 x 120 canvas and scaled to fit what it is given.
    static let canvas = CGSize(width: 200, height: 120)
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Group {
            switch kind {
            case .web: web
            case .app: app
            case .infra: infra
            case .other: docs
            }
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .accessibilityHidden(true)
    }

    private var line: Color { palette.text2.opacity(0.28) }

    /// One slow beat: `on` flips every 1.4 s while it animates, and stays true when it does not.
    private func beat<V: View>(@ViewBuilder _ content: @escaping (Bool) -> V) -> some View {
        Group {
            if animated {
                PhaseAnimator([false, true]) { content($0) } animation: { _ in .easeInOut(duration: 1.4) }
            } else {
                content(true)
            }
        }
    }

    private func bar(_ w: CGFloat, _ h: CGFloat = 6, _ colour: Color? = nil) -> some View {
        coreShape(2).fill(colour ?? line).frame(width: w, height: h)
    }

    // A browser window with a page that is live.
    private var web: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in coreShape(2).fill(line).frame(width: 6, height: 6) }
                coreShape(3).fill(GlassInk.wellHover).frame(height: 8).padding(.leading, 4)
            }
            beat { on in
                coreShape(Radius.chip).fill(hue.opacity(on ? 0.95 : (reduce ? 0.6 : 0.8)))
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 5) {
                            bar(on && !reduce ? 84 : 60, 8, .white.opacity(0.9))
                            bar(50, 5, .white.opacity(0.6))
                        }
                        .padding(.leading, 12)
                    }
            }
            .frame(height: 46)
            HStack(spacing: 6) { ForEach(0..<3, id: \.self) { _ in coreShape(Radius.chip).fill(GlassInk.wellHover) } }
                .frame(height: 28)
        }
        .padding(10).frame(width: 168, height: 104)
        .background(GlassInk.well, in: coreShape(Radius.control))
    }

    // A phone and the build line next to it: the bar fills as it builds.
    private var app: some View {
        HStack(spacing: 14) {
            coreShape(Radius.control).fill(GlassInk.wellHover).frame(width: 52, height: 96)
                .overlay {
                    coreShape(Radius.chip).fill(hue.opacity(0.9)).padding(5)
                        .overlay { Image(systemName: "hammer").foregroundStyle(.white) }
                }
            VStack(alignment: .leading, spacing: 8) {
                bar(70, 7, palette.text.opacity(0.55))
                bar(48, 5)
                beat { on in
                    coreShape(2).fill(GlassInk.wellHover).frame(width: 84, height: 8)
                        .overlay(alignment: .leading) {
                            coreShape(2).fill(hue).frame(width: reduce ? 58 : (on ? 84 : 20), height: 8)
                                .opacity(reduce ? (on ? 1 : 0.6) : 1)
                        }
                }
                bar(36, 5)
            }
        }
        .padding(12)
    }

    // Services as squares, healthy ones breathing in turn.
    private var infra: some View {
        beat { on in
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { c in
                            let lit = (r + c) % 2 == 0 ? on : !on
                            coreShape(Radius.control).fill(c == 1 && r == 0 ? hue : hue.opacity(lit ? 0.55 : 0.28))
                                .frame(width: 40, height: 40)
                                .overlay { Image(systemName: "server.rack").foregroundStyle(.white.opacity(0.85)) }
                        }
                    }
                }
            }
        }
    }

    // Two documents, the front one being written.
    private var docs: some View {
        beat { on in
            ZStack {
                coreShape(Radius.control).fill(GlassInk.wellHover).frame(width: 100, height: 84).offset(x: 22, y: -6)
                    .rotationEffect(.degrees(reduce ? 0 : 4))
                coreShape(Radius.control).fill(GlassInk.well).frame(width: 100, height: 84).offset(x: -14, y: 4)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            bar(46, 8, hue)
                            bar(on && !reduce ? 70 : 44)
                            bar(on || reduce ? 58 : 30)
                            bar(36)
                        }
                        .padding(12)
                    }
            }
        }
    }
}
