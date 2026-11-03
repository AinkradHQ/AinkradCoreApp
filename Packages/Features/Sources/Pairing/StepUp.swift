import CoreKit
import CoreUI
import Foundation
import Observation
import SwiftUI

/// The user said no to Touch ID, or closed the sheet after it failed: the action does not run.
struct StepUpDeclined: Error {}

/// What the one Touch ID sheet shows.
enum StepUpPhase: Equatable {
    case asking(String)
    case cancelled
    case failed(String)
    case noKey
    case refused(String)

    /// Sorts what `stepUp` threw. CoreKit names a cancelled prompt and a missing key only in the message.
    static func from(_ error: any Error) -> StepUpPhase {
        switch CoreError.unwrapping(error) {
        case .stepUpUnavailable(let m):
            return m.localizedCaseInsensitiveContains("cancel") ? StepUpPhase.cancelled : StepUpPhase.noKey
        case .keyStore: return StepUpPhase.failed("The Secure Enclave could not sign the request.")
        case .some(let e): return StepUpPhase.refused(e.localizedDescription)
        case nil: return StepUpPhase.failed(error.localizedDescription)
        }
    }
}

/// Touch ID (`Mac.stepUp`): one sheet for every elevated action. It waits for the system prompt, and when that ends without
/// an elevation it says why (cancelled is the person's choice, failed is not) and offers to try again.
@MainActor @Observable
final class StepUpModel {
    private(set) var phase: StepUpPhase?
    private var answer: CheckedContinuation<Bool, Never>?
    func set(_ p: StepUpPhase?) { phase = p }
    func wait() async -> Bool {
        await withCheckedContinuation { answer = $0 }
    }
    func choose(retry: Bool) {
        let a = answer
        answer = nil
        a?.resume(returning: retry)
    }
}

struct StepUpSheet: View {
    @Bindable var model: StepUpModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        DialogCard(title: title, width: Space.s8 * 12) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: symbol).font(.system(size: MacTextSize.large))
                        .foregroundStyle(palette.tone(tone).ink)
                        .frame(width: MacSize.controlLg, height: MacSize.controlLg)
                        .background(palette.tone(tone).fill, in: coreShape(Radius.control))
                        .accessibilityHidden(true)
                    Text(detail).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
                }
                if case .asking = model.phase {
                    HStack(spacing: Space.s2) {
                        Spin()
                        Text("Waiting for Touch ID").font(.system(size: MacTextSize.body, weight: .semibold))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.updatesFrequently)
                } else {
                    HStack(spacing: Space.s2) {
                        Spacer(minLength: 0)
                        Button(model.phase == .noKey ? "Close" : "Cancel") { model.choose(retry: false) }
                            .buttonStyle(.coreSecondary).keyboardShortcut(.cancelAction)
                        if model.phase != .noKey {
                            Button("Try again") { model.choose(retry: true) }
                                .buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .font(.system(size: MacTextSize.body))
        }
        .accessibilityIdentifier("stepup")
    }

    private var title: String {
        switch model.phase {
        case .asking, nil: "Confirm with Touch ID"
        case .cancelled: "Touch ID was cancelled"
        case .failed: "Touch ID didn't work"
        case .noKey: "This Mac can't confirm"
        case .refused: "The Core refused the proof"
        }
    }
    private var symbol: String {
        switch model.phase {
        case .asking, nil: "touchid"
        case .cancelled: "hand.raised"
        case .noKey: "lock.slash"
        default: "exclamationmark.triangle"
        }
    }
    private var tone: Tone {
        switch model.phase {
        case .asking, nil: .done
        case .cancelled: .queue
        default: .warn
        }
    }
    private var detail: String {
        switch model.phase {
        case .asking(let reason): reason
        case .cancelled: "You cancelled, so nothing changed. Try again when you are ready."
        case .failed(let m): "\(m) Try again. After a few misses macOS asks for your password instead."
        case .noKey: "A Mac with no step-up key can never unlock admin actions. Use another admin device for this."
        case .refused(let m): m
        case nil: ""
        }
    }
}
