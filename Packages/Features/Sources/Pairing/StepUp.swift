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
        case .asking: ""
        }
    }

    var detail: String {
        switch phase {
        case .cancelled:
            keepsEdit ? "Your edit is still here. Try again when you are ready." : "Try again when you are ready."
        case .failed(let m): "\(m) Try again. After a few misses macOS asks for your password instead."
        case .noKey: "A Mac with no step-up key can never unlock admin actions. Use another admin device for this."
        case .refused(let m): m
        case .asking: ""
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

/// The one Touch ID sheet. It shows only while the system prompt is up.
struct StepUpSheet: View {
    @Bindable var model: StepUpModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        DialogCard(title: "Confirm with Touch ID", width: Space.s8 * 12) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "touchid").font(.system(size: MacTextSize.large))
                        .foregroundStyle(palette.tone(.done).ink)
                        .frame(width: MacSize.controlLg, height: MacSize.controlLg)
                        .background(palette.tone(.done).fill, in: coreShape(Radius.control))
                        .accessibilityHidden(true)
                    Text(reason).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    IndBar()
                    Text("Waiting for Touch ID").font(.system(size: MacTextSize.body, weight: .semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
            .font(.system(size: MacTextSize.body))
        }
        .accessibilityIdentifier("stepup")
    }

    private var reason: String {
        if case .asking(let r)? = model.phase { return r }
        return ""
    }
}
