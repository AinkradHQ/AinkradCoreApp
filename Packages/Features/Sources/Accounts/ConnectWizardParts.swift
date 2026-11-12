import CoreUI
import SwiftUI

/// The words and small rules of the Connect an account wizard, kept out of the view so they can be tested.
enum ConnectWizardWords {
    /// The install bar's width on a provider row (accounts-connect.html: 140 pt).
    static let barWidth: CGFloat = Space.s8 * 4 + Space.s3
    /// The mockup's install bar is 6 pt tall, a touch heavier than the 4 pt meters on cards.
    static let barHeight: CGFloat = Space.s1 + Space.s1 / 2

    /// The dialog's title for a step: the panel names the step instead of a second heading inside it.
    static func title(_ step: ConnectWizardState.Step, provider: String, plan: Bool) -> String {
        switch step {
        case .provider: "Connect an account"
        case .key: plan ? "Sign in to \(provider)" : "Add your \(provider) key"
        case .name: "Name it and set a limit"
        case .place: "Where does it go?"
        }
    }

    /// The line under the install bar: "Installing on Oracle · 64%".
    static func installing(on runner: String, percent: Int) -> String { "Installing on \(runner) · \(percent)%" }

    /// Whether some runner offers the provider, or could after a one-click install. A provider no runner offers is shown
    /// dimmed and cannot be picked.
    static func offered(_ r: ProviderReadiness, installable: Bool) -> Bool {
        switch r {
        case .ready, .needsRunner: true
        case .notInstalled: installable
        }
    }
}

/// One provider in step 1: its tile, name and one line, and on the right its state (Ready, Install on…, the install bar,
/// or "No runner offers it"). A plain row inside the framed dialog: hover lifts the well, the chosen one gets the blue
/// edge, rows keep one height.
// Local part: CoreUI's RadioRow has no slot for a leading tile. Proposal: a `leading` view on RadioRow.
struct ProviderChoiceRow<Trailing: View>: View {
    let provider: String
    let title: String
    let line: String
    let selected: Bool
    let dim: Bool
    let pick: () -> Void
    @ViewBuilder let trailing: Trailing
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let shape = coreShape(Radius.row)
        // The row is a Button (keyboard, press), the trailing state sits beside it: it holds buttons of its own.
        HStack(spacing: Space.s3) {
            Button {
                if !dim { pick() }
            } label: {
                HStack(spacing: Space.s3) {
                    AccTile(provider: provider, dim: dim)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                        Text(line).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, Space.s3).padding(.vertical, Space.s1)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressReporting(pressed: $pressed))
            .accessibilityLabel("\(title), \(line)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            trailing.frame(minWidth: Space.s8 * 6, alignment: .trailing).padding(.trailing, Space.s3)
        }
        .frame(minHeight: Space.s8 + Space.s4)
        // The label fills the row's height; without this the rows share out the whole dialog's height.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            selected || (pressed && !dim) ? palette.uDimHover : hovering && !dim ? palette.uDim : .clear, in: shape
        )
        .overlay { if selected { shape.strokeBorder(palette.primary, lineWidth: 1.5) } }
        .scaleEffect(pressed && !dim && !reduce ? 0.99 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.press), value: pressed)
        .animation(reduce ? nil : Motion.out(Motion.hover), value: hovering)
        .animation(reduce ? nil : Motion.out(Motion.hover), value: selected)
        .accessibilityElement(children: .contain)
    }
}

/// A plain button that hands its pressed state up, so the whole row (not just the button) can press in.
private struct PressReporting: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, now in pressed = now }
    }
}
