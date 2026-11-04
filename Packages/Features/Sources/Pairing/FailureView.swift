import CoreUI
import SwiftUI

struct FailureAction: Identifiable {
    enum Style { case primary, secondary }
    let id = UUID()
    let label: String
    var style: Style = .secondary
    var disabled = false
    let run: () -> Void
}

extension Failure {
    var title: String {
        switch kind {
        case .offline: "Can't reach the Core"
        case .rateLimited: "Too many requests"
        case .identityMismatch: "This is not the Core you expected"
        case .unproven: "The Core could not prove who it is"
        case .clockSkew: "This Mac's clock is off"
        case .rejected: "The approver rejected this Mac"
        case .expired: "The pairing expired"
        case .badCode: "That code did not work"
        case .sasMismatch: "The check codes do not match"
        case .oldApp: "This app and the Core do not speak the same version"
        case .revokedHere: "This Mac was revoked"
        case .cancelledAfterApproval: "Pairing cancelled"
        case .keychain: "The keychain refused"
        case .other: "Something went wrong"
        }
    }

    var code: String? {
        switch kind {
        case .rateLimited: "429 rate_limited"
        case .identityMismatch: "core_identity_mismatch"
        case .clockSkew: "401 clock_skew"
        case .rejected: "status: rejected"
        case .badCode: "401 pairing_failed"
        case .sasMismatch: "409 sas_mismatch"
        case .oldApp: "api_minor"
        default: nil
        }
    }

    var symbol: String {
        switch kind {
        case .offline: "wifi.slash"
        case .rateLimited, .clockSkew, .expired: "clock"
        case .identityMismatch, .unproven, .sasMismatch: "exclamationmark.shield"
        case .rejected, .revokedHere: "xmark"
        default: "exclamationmark.triangle"
        }
    }

    var tone: Tone { fatal || kind == .rejected ? .fail : .warn }

    var text: String {
        switch kind {
        case .offline(let m):
            "There was no answer, so nothing was sent from this Mac. \(m) Ainkrad does not keep retrying in the background."
        case .rateLimited: "This address asked the Core too often. Waiting is the only thing that helps."
        case .identityMismatch:
            "The Core that answered has a different identity from the one this Mac expected. It stopped before sending anything signed, so nothing left this Mac. Only pair again if the Core's identity was changed on purpose."
        case .unproven:
            "The Core did not answer the identity check properly. This Mac sent nothing signed. Try again in a moment."
        case .clockSkew(let server):
            "Signed requests are refused when the two clocks differ by more than 60 seconds. \(Self.skew(server))Turn on Set time automatically in System Settings, General, Date & Time."
        case .rejected:
            "This Mac was not added to the Core. Its keys were discarded. If it was a mistake, ask for a new code."
        case .expired: "A pairing lasts 5 minutes. Ask the approver for a new code."
        case .badCode:
            "The code is wrong, already used or past its 5 minutes. A code works once. After a few wrong tries the Core stops accepting codes from this address."
        case .sasMismatch:
            "This Mac worked out a different check code from the one the Core sent. Nothing was approved."
        case .oldApp:
            "This app and the Core share no API version, so nothing is sent. Update the app or the Core, then connect again."
        case .revokedHere:
            "Another admin device removed this Mac from the Core. Its keys are gone from here. Pair again to come back."
        case .cancelledAfterApproval(let id):
            "The approver had already approved this Mac, so it is still listed on their side. Ask them to revoke device \(id) in Settings, Devices."
        case .keychain(let m): m
        case .other(let m): m
        }
    }

    var reasons: [String] {
        if case .offline = kind {
            return [
                "The Core is off or restarting", "The address or port is wrong",
                "A Core on your home network needs you on that network or its tunnel",
            ]
        }
        return []
    }

    private static func skew(_ server: Int64?) -> String {
        guard let server else { return "" }
        let diff = Int(Date().timeIntervalSince1970) - Int(server)
        let how = diff > 0 ? "ahead of" : "behind"
        return "This Mac is \(abs(diff)) seconds \(how) the Core. "
    }
}

/// A failure, in words and with the next step: the same card for first run and for a lost connection.
struct FailureView: View {
    let failure: Failure
    var retryAt: Date?
    let actions: [FailureAction]
    @Environment(\.corePalette) private var palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in card(now: context.date) }
    }

    private func card(now: Date) -> some View {
        let wait = max(0, Int((retryAt ?? now).timeIntervalSince(now).rounded(.up)))
        return VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: failure.symbol).font(.system(size: MacTextSize.large))
                    .foregroundStyle(palette.tone(failure.tone).ink)
                    .frame(width: MacSize.controlLg, height: MacSize.controlLg)
                    .background(palette.tone(failure.tone).fill, in: coreShape(Radius.control))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(failure.title).font(.system(size: MacTextSize.large, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let code = failure.code {
                        Text(code).font(.system(size: MacTextSize.meta, design: .monospaced))
                            .foregroundStyle(palette.text2)
                    }
                }
            }
            Text(failure.text).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
            if !failure.reasons.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(failure.reasons, id: \.self) { Text("• \($0)") }
                }
                .foregroundStyle(palette.text2)
            }
            if wait > 0 {
                Label(
                    "The Core answers again in \(wait / 60):\(String(format: "%02d", wait % 60)).", systemImage: "clock"
                )
                .font(.system(size: MacTextSize.body, weight: .semibold))
            }
            if failure.fatal {
                Label("Stopped. There is no way to continue from here.", systemImage: "hand.raised")
                    .font(.system(size: MacTextSize.body, weight: .semibold))
            }
            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                ForEach(actions) { a in
                    if a.style == .primary {
                        Button(a.label, action: a.run).buttonStyle(.coreProminent).keyboardShortcut(.defaultAction)
                            .disabled(a.disabled || wait > 0)
                    } else {
                        Button(a.label, action: a.run).buttonStyle(.coreSecondary).disabled(a.disabled)
                    }
                }
            }
        }
        .font(.system(size: MacTextSize.body))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("failure")
    }
}
