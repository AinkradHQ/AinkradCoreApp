import CoreUI
import SwiftUI

/// A step arriving: it slides in from the trailing side going forward and from the leading side going back, and the old one
/// is replaced at once. Reduce Motion fades without moving.
struct ConnStage<Content: View>: View {
    let step: Int
    @ViewBuilder let content: Content
    init(step: ConnStep, @ViewBuilder content: () -> Content) { self.init(index: step.rawValue, content: content) }
    /// Any numbered way of steps (Add an AI account's Pick · Add · Done).
    init(index: Int, @ViewBuilder content: () -> Content) {
        step = index
        self.content = content()
    }
    @State private var arrived = 1.0
    @State private var from: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        content
            .id(step)
            .frame(maxWidth: .infinity)
            .offset(x: reduce ? 0 : (1 - arrived) * from * 32)  // grid: ok motion only, the slide of a step
            .opacity(arrived)
            .onChange(of: step) { old, new in
                from = new >= old ? 1 : -1
                arrived = 0
                withAnimation(Motion.calm(Motion.out(Motion.move), reduce)) { arrived = 1 }
            }
    }
}

/// A service as a card in the dialog's grid: logo, name, one line.
struct ConnPickCard: View {
    let kind: ConnKind
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.s3) {
                ConnLogo(kind: kind.id, size: 36, lit: hover)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.name).coreFont(size: MacTextSize.body, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(kind.say).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassInk.well, in: coreShape(Radius.cardMac))
            .contentShape(coreShape(Radius.cardMac))
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.cardMac, hoverFill: true))
        .onHover { hover = $0 }
        .accessibilityLabel("\(kind.name). \(kind.say)")
    }
}

/// The service's logo and the Core with the moving dots between them.
struct ConnPair: View {
    let kind: String
    var size: CGFloat = 64
    var body: some View {
        HStack(spacing: Space.s4) {
            ConnLogo(kind: kind, size: size)
            ConnLink()
            ConnCoreTile(size: size)
        }
    }
}

/// One line of the sign-in checklist: a numbered badge (a tick when done), a title and a line under it, and an action.
struct ConnCheckRow<Trailing: View>: View {
    let index: Int
    let item: ConnSignInItem
    var detail: AnyView?
    let trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                coreShape(Radius.control).fill(item.state == .current ? GlassInk.wellHover : GlassInk.well)
                if item.state == .done {
                    Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold)
                        .foregroundStyle(GlassInk.green)
                } else {
                    Text("\(index)").coreFont(size: MacTextSize.meta, weight: .semibold)
                        .foregroundStyle(item.state == .current ? GlassInk.primary : GlassInk.secondary)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).coreFont(size: MacTextSize.body, weight: .semibold)
                    .foregroundStyle(item.state == .todo ? GlassInk.secondary : GlassInk.primary)
                if let detail {
                    detail
                } else if let d = item.detail {
                    Text(d).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            .layoutPriority(detail == nil ? 0 : 1)  // a field in the line takes the width before the spacer
            Spacer(minLength: Space.s3)
            trailing
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassInk.well, in: coreShape(Radius.cardMac))
        .animation(Motion.out(Motion.ui), value: item.state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Step \(index): \(item.title)\(item.state == .done ? ", done" : "")")
    }
}

/// The dialog footer: Cancel (esc) and Back on the left, an optional quiet action and the main one on the right.
struct ConnFooter: View {
    let cancel: () -> Void
    var back: (() -> Void)?
    var alternate: (String, () -> Void)?
    var primary: (String, () -> Void)?
    var enabled = true
    var busy = false

    var body: some View {
        HStack(spacing: Space.s2) {
            Button("Cancel", action: cancel).buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
            if let back { Button("Back", action: back).buttonStyle(CoreButtonStyle(.secondary)) }
            Spacer(minLength: Space.s3)
            if let alternate {
                Button(alternate.0, action: alternate.1).buttonStyle(CoreButtonStyle(.secondary))
            }
            if let primary {
                Button(primary.0) { if !busy { primary.1() } }
                    .buttonStyle(CoreButtonStyle(.prominent, busy: busy)).coreShortcut(.primary).disabled(!enabled)
            }
        }
    }
}
