#if DEBUG && os(macOS)
import SwiftUI

@available(macOS 26, *)
extension OfficialGlassSection {
    var customSurfaces: some View {
        group(
            "Cards and custom surfaces",
            note: "glassEffect is for the control layer. Content cards stay material (corePanel), never glass on glass."
        ) {
            item(".glassEffect(.regular | .clear, in: .rect(cornerRadius: 8))") {
                HStack {
                    card("regular").glassEffect(.regular, in: .rect(cornerRadius: 8))
                    card("clear").glassEffect(.clear, in: .rect(cornerRadius: 8))
                }
            }
            item(".glassEffect(.regular.tint(blue) | .regular.interactive(), in: …)") {
                HStack {
                    card("tint").glassEffect(.regular.tint(blue.opacity(0.5)), in: .rect(cornerRadius: 8))
                    card("interactive").glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                }
            }
            item("GlassEffectContainer + glassEffectID(_, in: namespace): tap to morph") {
                morph
            }
            item("GlassEffectContainer + glassEffectUnion(id:namespace:): tap to split") {
                unionDemo
            }
            item("ConcentricRectangle() + .containerShape(.rect(cornerRadius: 16)): inner = 16 − 8") {
                Text("Outer 16, inset 8, inner concentric").font(.system(size: MacTextSize.meta))
                    .padding(Space.s2).frame(maxWidth: .infinity)
                    .glassEffect(.regular, in: ConcentricRectangle())
                    .padding(Space.s2)
                    .containerShape(.rect(cornerRadius: 16))
                    // Material, not glass: no glass on glass.
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        } core: {
            item(".coreGlass() (Glass.regular.tint(deep blue).interactive(), dark scheme forced)") {
                Label("Glass control", systemImage: "square.dashed").padding(Space.s3).coreGlass()
            }
            item(".coreGlass(interactive: false)") {
                Label("Static glass", systemImage: "square.dashed").padding(Space.s3).coreGlass(interactive: false)
            }
            item(".corePanel() regular material, content surface") {
                Text("Panel content").corePanel()
            }
            item(".coreCard(palette.glassCard, radius:) tint on a row") {
                Text("Card tint").padding(Space.s3).coreCard(palette.glassCard, radius: Radius.cardMac)
            }
            Text("CoreUI has no container, morph, union or concentric shape: each coreGlass is a separate glass.")
                .font(.system(size: MacTextSize.meta)).opacity(0.8)
        }
    }

    private func card(_ name: String) -> some View {
        Text(name).font(.system(size: MacTextSize.body)).padding(Space.s4).frame(maxWidth: .infinity)
    }

    private var morph: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button(morphed ? "Collapse" : "Expand") {
                withAnimation(reduceMotion ? Motion.out(Motion.hover) : .smooth) { morphed.toggle() }
            }
            .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 8))
            GlassEffectContainer(spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "pencil").frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                        .glassEffectID("a", in: ns)
                    if morphed {
                        Image(systemName: "trash").frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                            .glassEffectID("b", in: ns)
                            .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                        Image(systemName: "square.and.arrow.up").frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                            .glassEffectID("c", in: ns)
                            .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                    }
                }
            }
        }
    }

    private var unionDemo: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button(union ? "Split" : "Merge") {
                withAnimation(reduceMotion ? Motion.out(Motion.hover) : .smooth) { union.toggle() }
            }
            .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 8))
            GlassEffectContainer(spacing: Space.s4) {
                HStack(spacing: union ? Space.s1 : Space.s4) {
                    ForEach(["bold", "italic", "underline"], id: \.self) { name in
                        Image(systemName: name).frame(width: 32, height: 32)
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                            .glassEffectUnion(id: union ? "u" : name, namespace: ns)
                    }
                }
            }
        }
    }
}
#endif
