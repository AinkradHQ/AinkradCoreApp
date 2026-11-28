import CoreUI
import SwiftUI

/// The gallery's own centred state (offline, failed, no match): glyph, title, line and the actions, all on one axis. The
/// shared state card right-aligns its button under centred text, which looked off here.
struct GalleryState: View {
    struct Action: Identifiable {
        var id: String { title }
        let title: String
        var prominent = false
        var disabled = false
        let run: () -> Void
    }
    let symbol: String
    let title: String
    let line: String
    let actions: [Action]
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: symbol).coreFont(size: MacTextSize.large, weight: .semibold)
                .foregroundStyle(palette.text2).accessibilityHidden(true)
            Text(title).coreFont(size: MacTextSize.title, weight: .semibold).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(line).foregroundStyle(palette.text2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s2) {
                ForEach(actions) { a in
                    Button(a.title, action: a.run)
                        .buttonStyle(CoreButtonStyle(a.prominent ? .prominent : .secondary, size: .small))
                        .disabled(a.disabled)
                }
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: Space.s8 * 11)
        .coreWell()
        .accessibilityElement(children: .contain)
    }
}
