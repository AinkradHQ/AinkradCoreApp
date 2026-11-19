import CoreUI
import SwiftUI

/// Working hours that are flexible (Ahmed, 2026-11-19): set hours with a range per day and a second range to split a day,
/// "it varies", or "on call" with quiet hours instead.
struct SetupHoursPage: View {
    @Binding var profile: SetupProfile
    @Environment(\.corePalette) private var palette

    var body: some View {
        SetupPage(
            meta: "About you · 3 of 5", title: "When do you work?",
            sub: "Pick your days and times. Add a second range to split a day, or say it varies."
        ) {
            CoreSegmented(
                "How you work",
                segments: [
                    CoreSegment(SetupProfile.HoursMode.set, "Set hours"), CoreSegment(.vary, "It varies"),
                    CoreSegment(.onCall, "On call"),
                ], selection: $profile.hoursMode)
            switch profile.hoursMode {
            case .set: setHours
            case .vary:
                note("sparkles", "Your days change, and that is fine",
                    "Ainkrad learns your rhythm from when you are active, and only asks when it is unsure.")
            case .onCall:
                note("bell", "Any hour can be work time", "The AI can reach you any time, except your quiet hours.")
                axis
                HStack(spacing: Space.s3) {
                    Text("Quiet").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).frame(width: 52, alignment: .leading)
                    track(
                        profile.quiet, empty: "No quiet hours",
                        menu: [("Night · 22 to 6", [.init(from: 22, to: 24), .init(from: 0, to: 6)]),
                            ("Late night · 0 to 7", [.init(from: 0, to: 7)]),
                            ("Early · 23 to 7", [.init(from: 23, to: 24), .init(from: 0, to: 7)])],
                        remove: ("No quiet hours", { profile.quiet = [] })
                    ) { profile.quiet = $0 }
                }
            }
            CoreSelect(
                "Time zone", selection: $profile.timeZone,
                options: Self.zones(including: profile.timeZone).map { CoreSelectOption($0, Self.label($0)) })
        }
    }

    // MARK: set hours

    private var setHours: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            SetupFlow {
                ForEach(Array(SetupProfile.quickHours.enumerated()), id: \.offset) { _, q in
                    Button {
                        profile.applyQuick(q.1)
                    } label: {
                        Text("\(q.0)  \(q.1.from) to \(q.1.to)").coreFont(size: MacTextSize.body, weight: .medium)
                            .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
                            .background(GlassInk.well, in: coreShape(Radius.control))
                    }
                    .buttonStyle(CoreQuietPressStyle())
                }
            }
            axis
            ForEach(SetupProfile.days, id: \.self) { d in
                let bands = profile.hours[d] ?? []
                HStack(spacing: Space.s3) {
                    Button {
                        profile.toggleDay(d)
                    } label: {
                        Text(d).coreFont(size: MacTextSize.body, weight: .medium)
                            .frame(width: 52, height: MacSize.controlSm)
                            .foregroundStyle(bands.isEmpty ? palette.text2 : palette.text)
                            .background(bands.isEmpty ? GlassInk.well : palette.navActive, in: coreShape(Radius.chip))
                    }
                    .buttonStyle(CoreQuietPressStyle())
                    .accessibilityLabel("\(d), \(bands.isEmpty ? "day off" : "working")")
                    track(
                        bands, empty: "Day off",
                        menu: [("Morning · 6 to 12", [.init(from: 6, to: 12)]), ("Day · 9 to 17", [.init(from: 9, to: 17)]),
                            ("Afternoon · 13 to 18", [.init(from: 13, to: 18)]), ("Evening · 18 to 23", [.init(from: 18, to: 23)]),
                            ("Late · 20 to 24", [.init(from: 20, to: 24)])],
                        remove: ("Remove this range", nil), day: d, quiet: false
                    ) { _ in }
                    CoreIconButton(symbol: "plus", label: "Add another range") { profile.addRange(d) }
                }
            }
        }
    }

    private var axis: some View {
        HStack(spacing: Space.s3) {
            Color.clear.frame(width: 52, height: 1)
            GeometryReader { g in
                ForEach([0, 6, 12, 18, 24], id: \.self) { n in
                    Text("\(n)").coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                        .position(x: g.size.width * CGFloat(n) / 24, y: 7)
                }
            }
            .frame(height: 14)
            Color.clear.frame(width: MacSize.controlMd, height: 1)
        }
    }

    /// One day's track: a band per range on a 24 hour line. Tapping a band offers other ranges, or removes it.
    private func track(
        _ bands: [SetupProfile.Band], empty: String, menu: [(String, [SetupProfile.Band])],
        remove: (String, (() -> Void)?), day: String? = nil, quiet: Bool = true,
        set: @escaping ([SetupProfile.Band]) -> Void
    ) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                coreShape(Radius.chip).fill(GlassInk.well)
                if bands.isEmpty {
                    Text(empty).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2).padding(.leading, Space.s3)
                }
                ForEach(Array(bands.enumerated()), id: \.offset) { i, b in
                    let w = g.size.width
                    CoreDropdown(items: items(i, menu: menu, remove: remove, day: day, set: set)) {
                        coreShape(Radius.chip).fill(quiet ? palette.text2.opacity(0.6) : palette.primary)
                            .overlay {
                                if b.to - b.from >= 3 {
                                    Text(b.text).coreFont(size: MacTextSize.meta, weight: .semibold).foregroundStyle(.white)
                                }
                            }
                            .frame(width: max(8, w * CGFloat(b.to - b.from) / 24), height: g.size.height - 4)
                    }
                    .offset(x: w * CGFloat(b.from) / 24)
                    .accessibilityLabel("\(b.from) to \(b.to). Change this range")
                }
            }
        }
        .frame(height: MacSize.controlMd)
    }

    private func items(
        _ i: Int, menu: [(String, [SetupProfile.Band])], remove: (String, (() -> Void)?), day: String?,
        set: @escaping ([SetupProfile.Band]) -> Void
    ) -> [CoreDropdownItem] {
        var out = menu.map { m in
            CoreDropdownItem(m.0) {
                if let day { profile.setRange(day, at: i, to: m.1[0]) } else { set(m.1) }
            }
        }
        out.append(
            CoreDropdownItem(remove.0, symbol: "trash", destructive: true) {
                if let day { profile.setRange(day, at: i, to: nil) } else { remove.1?() }
            })
        return out
    }

    private func note(_ symbol: String, _ title: String, _ text: String) -> some View {
        CoreNotice(symbol: symbol, title: title, text: text) {}
    }

    // MARK: zones

    private static func zones(including current: String) -> [String] {
        let common = ["Europe/Berlin", "Europe/London", "America/New_York", "America/Los_Angeles", "Asia/Dubai", "Asia/Tokyo"]
        return Array(NSOrderedSet(array: [current] + common)) as? [String] ?? [current]
    }

    private static func label(_ id: String) -> String {
        guard let z = TimeZone(identifier: id) else { return id }
        let h = z.secondsFromGMT() / 3600
        return "\(id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id) (UTC\(h >= 0 ? "+" : "")\(h))"
    }
}
