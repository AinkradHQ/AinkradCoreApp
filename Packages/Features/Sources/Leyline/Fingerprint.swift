import CoreUI
import Foundation
import SwiftUI

/// A host key as a pattern: 8 by 4 rounded squares in four tones, made from the SHA256 of the key, so the same key always
/// looks the same and a changed key looks different at a glance. The words and the `SHA256:` text stay beside it; the pattern
/// is only an aid to the eye, never the proof.
/// TODO(design-system): proposal CoreFingerprint (the pattern as a shared component; the pairing check codes could use it).
struct FingerprintPattern: View {
    let fingerprint: String
    var cell: CGFloat = Space.s3
    nonisolated static let columns = 8
    nonisolated static let rows = 4

    /// One tone (0 to 3) per cell, left to right and top to bottom. Every byte of the digest counts: a cell folds its
    /// byte's four 2-bit pairs, so one changed byte changes its cell. Not a SHA256 string: a flat pattern, never a crash.
    nonisolated static func tones(_ fingerprint: String) -> [Int] {
        let bytes = digest(fingerprint)
        let count = columns * rows
        guard bytes.count == count else { return Array(repeating: 0, count: count) }
        return bytes.map { Int(($0 ^ ($0 >> 2) ^ ($0 >> 4) ^ ($0 >> 6)) & 3) }
    }

    /// The 32 bytes of `SHA256:<base64 without padding>`; empty for anything else.
    nonisolated static func digest(_ fingerprint: String) -> [UInt8] {
        guard fingerprint.hasPrefix("SHA256:") else { return [] }
        var b64 = String(fingerprint.dropFirst("SHA256:".count)).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64).map { [UInt8]($0) } ?? []
    }

    /// "SHA256:lan…9Zp": the start and the end of the digest, for a row that is too narrow for the whole.
    nonisolated static func short(_ fingerprint: String) -> String {
        let body = fingerprint.hasPrefix("SHA256:") ? String(fingerprint.dropFirst(7)) : fingerprint
        guard body.count > 8 else { return fingerprint }
        return "SHA256:\(body.prefix(3))…\(body.suffix(3))"
    }

    var body: some View {
        let tones = Self.tones(fingerprint)
        let gap = Space.s1 - 1
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<Self.rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<Self.columns, id: \.self) { c in
                        coreShape(Radius.chip / 2).fill(Self.ink(tones[r * Self.columns + c]))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Host key pattern")
        .accessibilityValue(Self.short(fingerprint))
    }

    private static func ink(_ tone: Int) -> Color {
        switch tone {
        case 0: GlassInk.primary
        case 1: GlassInk.secondary
        case 2: GlassInk.secondary.opacity(0.5)
        default: GlassInk.well
        }
    }
}
