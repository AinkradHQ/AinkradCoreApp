import AppKit
import CoreKit
import CoreUI
import Foundation
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import Observation
import SwiftUI

/// The person said no to Touch ID, or it did not elevate: the action does not run. The reason is in `AppModel.stepUpNotice`.
struct StepUpDeclined: Error {}

/// What the Touch ID sheet shows while asking, and what an inline notice says after.
enum StepUpPhase: Equatable {
    case asking(String)
    /// Touch ID went through: the sheet shows a tick for a moment before it closes.
    case done
    case cancelled
    case failed(String)
    case noKey
    case refused(String)

    /// Sorts what `stepUp` threw into the person's choice (cancelled), the device (no key, failed) or the Core (refused).
    static func from(_ error: any Error) -> StepUpPhase {
        switch CoreError.unwrapping(error) {
        case .stepUpCancelled: return StepUpPhase.cancelled
        case .stepUpUnavailable: return StepUpPhase.noKey
        case .keyStore: return StepUpPhase.failed("The Secure Enclave could not sign the request.")
        case .some(let e): return StepUpPhase.refused(e.localizedDescription)
        case nil: return StepUpPhase.failed(error.localizedDescription)
        }
    }
}

/// Why an elevated action did not run, in context: shown inline in the panel that asked, never as a second modal.
struct StepUpNotice: Equatable {
    let phase: StepUpPhase
    /// What did not happen: "renamed", "revoked", "changed", "cleared", "approved", "made".
    let done: String
    /// True where the person's input is still on screen (a dialog), so the copy can say "Your edit is still here."
    var keepsEdit = true

    var title: String {
        switch phase {
        case .cancelled: "Cancelled, nothing was \(done)."
        case .failed: "Touch ID didn't match. Nothing was \(done)."
        case .noKey: "This Mac can't confirm. Nothing was \(done)."
        case .refused: "The Core refused the proof. Nothing was \(done)."
        case .asking, .done: ""
        }
    }

    var detail: String {
        switch phase {
        case .cancelled:
            keepsEdit ? "Your edit is still here. Try again when you are ready." : "Try again when you are ready."
        case .failed(let m): "\(m) Try again. After a few misses macOS asks for your password instead."
        case .noKey: "A Mac with no step-up key can never unlock admin actions. Use another admin device for this."
        case .refused(let m): m
        case .asking, .done: ""
        }
    }

    var symbol: String {
        switch phase {
        case .cancelled: "hand.raised"
        case .noKey: "lock.slash"
        default: "exclamationmark.triangle"
        }
    }

    var tone: Tone { phase == .cancelled ? .queue : .warn }
}

/// What the Touch ID sheet knows: the phase it is asking in.
@MainActor @Observable
final class StepUpModel {
    private(set) var phase: StepUpPhase?
    /// The context the embedded Touch ID view and the Secure Enclave signature share (one per ask).
    private(set) var context = LAContext()
    func set(_ p: StepUpPhase?) {
        if case .asking = p {
            context = LAContext()
            StepUpAuthContext.prepare(context)
        }
        phase = p
    }

    private var choice: CheckedContinuation<Bool, Never>?

    /// Asks for Touch ID in the sheet's embedded view and waits. True once it went through. A miss shows in the sheet and
    /// waits for Try again (asks again) or Cancel (false); Esc cancels while it is asking.
    func confirm(_ reason: String) async -> Bool {
        cancelled = false
        // Let the sheet and its Touch ID view lay out before asking: the view cancels itself while it is still sizing.
        try? await Task.sleep(for: .milliseconds(300))
        while true {
            do {
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                return true
            } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
                if cancelled { return false }
                phase = .failed("Touch ID stopped before it finished.")
            } catch {
                phase = .failed(error.localizedDescription)
            }
            let again = await withCheckedContinuation { choice = $0 }
            choice = nil
            guard again else { return false }
            set(.asking(reason))
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private var cancelled = false

    /// The sheet's buttons and keys: Try again (↩) after a miss, Cancel (esc) at any time.
    func retry() { choice?.resume(returning: true) }
    func cancel() {
        cancelled = true
        context.invalidate()
        choice?.resume(returning: false)
    }
}

/// The inline outcome of a Touch ID that did not elevate: a banner in the panel, with the words from the prototype.
struct StepUpBanner: View {
    let app: AppModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        if let n = app.stepUpNotice {
            let colours = palette.tone(n.tone)
            HStack(alignment: .top, spacing: Space.s3) {
                IconTile(n.symbol, hue: colours.ink, size: 32, bounce: n.title)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(n.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(n.detail).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(colours.ink.opacity(0.14), in: coreShape(Radius.cardMac))
            .overlay { coreShape(Radius.cardMac).strokeBorder(colours.ink.opacity(0.35), lineWidth: 1) }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stepup-notice")
        }
    }
}

/// The one Touch ID sheet. It shows only while the system prompt is up: a fingerprint that scans, a tick when it goes through, a
/// small shake when it does not match.
struct StepUpSheet: View {
    @Bindable var model: StepUpModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var ripple = false
    @State private var sweep = false
    @State private var drawn: CGFloat = 0
    /// Esc and Return are caught here first: the window's own Esc handler leaves this sheet alone (it is not dismissible).
    @State private var keys: Any?

    private var hue: Color { done ? GlassInk.green : missed ? GlassInk.red : GlassInk.blue }

    var body: some View {
        VStack(spacing: Space.s4) {
            ZStack {
                // Halos rippling out while it waits (rounded rectangles, like every shape in the app).
                if !done && !missed && !reduce {
                    ForEach(0..<3, id: \.self) { i in
                        coreShape(Radius.cardMac + 10).stroke(hue.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 112, height: 112)
                            .scaleEffect(ripple ? 1.55 : 1)
                            .opacity(ripple ? 0 : 0.8)
                            .animation(
                                .easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(Double(i) * 0.7),
                                value: ripple)
                    }
                }
                coreShape(Radius.cardMac + 6)
                    .fill(
                        LinearGradient(
                            colors: [hue.opacity(0.55), hue.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay { coreShape(Radius.cardMac + 6).strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .frame(width: 112, height: 112)
                    .shadow(color: hue.opacity(0.6), radius: done ? 30 : 18)
                // A light sweep across the tile while it waits, under the Touch ID view: Apple's view cancels when anything
                // covers it.
                if !done && !missed && !reduce {
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(width: 112, height: 26)
                        .offset(y: sweep ? 46 : -46)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: sweep)
                        .clipShape(coreShape(Radius.cardMac + 6))
                        .frame(width: 112, height: 112)
                        .allowsHitTesting(false)
                }
                Group {
                    if done {
                        CheckMark().trim(from: 0, to: drawn)
                            .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                            .frame(width: 46, height: 46)
                            .transition(.scale.combined(with: .opacity))
                    } else if missed {
                        Image(systemName: "xmark").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Apple's own Touch ID view, inside this sheet: macOS asks here instead of a second panel.
                        // Fixed size, never animated: it cancels itself if it lays out while sizing.
                        LocalAuthenticationView("Touch ID", context: model.context)
                            .frame(width: 64, height: 64)
                            .transaction { $0.animation = nil }
                    }
                }
            }
            .frame(width: 170, height: 170)
            .modifier(Shake(count: missed && !reduce ? 3 : 0))
            .animation(.linear(duration: 0.45), value: missed)
            .animation(.spring(duration: 0.4, bounce: 0.35), value: done)
            .accessibilityHidden(true)
            VStack(spacing: Space.s2) {
                Text(done ? "Unlocked" : missed ? "Didn't match" : "Touch the sensor")
                    .font(.system(size: MacTextSize.large + 6, weight: .bold))
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    done
                        ? "Admin actions are open for a short while."
                        : missed ? "Touch it again. After a few misses macOS asks for your password." : reason
                )
                .foregroundStyle(GlassInk.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            }
            if missed {
                HStack(spacing: Space.s2) {
                    Button("Cancel") { model.cancel() }.buttonStyle(CoreButtonStyle(.secondary)).coreShortcut(.cancel)
                    Spacer(minLength: 0)
                    Button("Try again") { model.retry() }.buttonStyle(CoreButtonStyle(.prominent)).coreShortcut(
                        .primary)
                }
            } else if !done {
                Button("Cancel") { model.cancel() }.buttonStyle(CoreButtonStyle(.plain)).coreShortcut(.cancel)
                HStack(spacing: Space.s2) {
                    Image(systemName: "touchid").symbolEffect(.pulse, options: .repeating, isActive: !reduce)
                    Text("Waiting for Touch ID").font(.system(size: MacTextSize.body, weight: .semibold))
                }
                .foregroundStyle(GlassInk.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .foregroundStyle(GlassInk.primary)
        .padding(Space.s6)
        .frame(width: Space.s8 * 13)
        .corePanel(radius: Radius.panel + Space.s1, padding: 0)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        // No fade or scale on the way in: Apple's Touch ID view cancels while it is see-through or still sizing.
        .onAppear {
            ripple = true
            sweep = true
            keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                switch e.keyCode {
                case 53:  // Esc
                    model.cancel()
                    return nil
                case 36,
                    76 where missed:  // Return: Try again after a miss
                    model.retry()
                    return nil
                default: return e
                }
            }
        }
        .onDisappear { if let keys { NSEvent.removeMonitor(keys) } }
        .onChange(of: done) { _, now in
            if now { withAnimation(.easeOut(duration: reduce ? 0.01 : 0.4).delay(0.1)) { drawn = 1 } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm with Touch ID")
        .accessibilityIdentifier("stepup")
    }

    private var done: Bool { model.phase == .done }
    private var missed: Bool {
        if case .failed? = model.phase { return true }
        return false
    }

    private var reason: String {
        if case .asking(let r)? = model.phase { return r }
        return ""
    }
}

/// A tick drawn as one path, so it can draw itself in.
private struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.midY + r.height * 0.02))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.4, y: r.maxY - r.height * 0.18))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.minY + r.height * 0.18))
        return p
    }
}

/// A few small sideways steps: the sign that the fingerprint did not match.
private struct Shake: GeometryEffect {
    var count: CGFloat
    var animatableData: CGFloat {
        get { count }
        set { count = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(count * .pi * 2), y: 0))
    }
}
