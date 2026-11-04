import CoreKit
import CoreUI
import Foundation
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
    func set(_ p: StepUpPhase?) { phase = p }
}

/// The inline outcome of a Touch ID that did not elevate: a banner in the panel, with the words from the prototype.
struct StepUpBanner: View {
    let app: AppModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        if let n = app.stepUpNotice {
            let colours = palette.tone(n.tone)
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: n.symbol).foregroundStyle(colours.ink).frame(width: Space.s4).accessibilityHidden(
                    true)
                VStack(alignment: .leading, spacing: Space.s1 / 2) {
                    Text(n.title).font(.system(size: MacTextSize.headline, weight: .semibold))
                    Text(n.detail).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(palette.glassCard, in: coreShape(Radius.cardMac))
            .background(colours.fill, in: coreShape(Radius.cardMac))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("stepup-notice")
        }
    }
}

/// The one Touch ID sheet. It shows only while the system prompt is up: a fingerprint that scans, a tick when it goes through, a
/// small shake when it does not match.
struct StepUpSheet: View {
    @Bindable var model: StepUpModel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var scan = false

    var body: some View {
        // Centred, as the prototype's sheet: the tile, the title, what it is for, then the wait.
        VStack(spacing: Space.s3) {
            Image(systemName: done ? "checkmark" : missed ? "xmark" : "touchid")
                .font(.system(size: MacTextSize.large * 1.5))
                .foregroundStyle(palette.tone(missed ? .warn : .done).ink)
                .frame(width: MacSize.controlLg * 2, height: MacSize.controlLg * 2)
                .background(palette.tone(missed ? .warn : .done).fill, in: coreShape(Radius.cardMac))
                .opacity(scan && !done && !missed && !reduce ? 0.55 : 1)
                .animation(
                    reduce || done || missed ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: scan
                )
                .modifier(Shake(count: missed && !reduce ? 3 : 0))
                .animation(.linear(duration: 0.45), value: missed)
                .accessibilityHidden(true)
            Text("Confirm with Touch ID").font(.system(size: MacTextSize.title, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(done ? "Unlocked." : missed ? "Touch ID didn't match." : reason)
                .foregroundStyle(palette.text2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !done && !missed {
                VStack(spacing: Space.s1) {
                    IndBar()
                    Text("Waiting for Touch ID").font(.system(size: MacTextSize.body, weight: .semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .font(.system(size: MacTextSize.body))
        .foregroundStyle(palette.text)
        .corePanel(radius: Radius.panel, padding: Space.s6)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .frame(width: Space.s8 * 12)
        .onAppear { scan = true }
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
