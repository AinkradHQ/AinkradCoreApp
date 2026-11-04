import CoreUI
import SwiftUI

/// Settings, Security, Secrets: names and metadata, plus the leases this Mac granted. Values are write-only.
struct SecretsSection: View {
    let admin: AdminModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        let model = admin.secrets!
        AdminScreen(
            admin: admin, what: "Secrets",
            intro:
                "Values go in and never come back: there is no show and no copy. What you see is the name, the size, the version and who may lease it.",
            state: model.state,
            empty: ("No secrets yet", "Add a throwaway value to lease it to a runner.", "key"),
            emptyAction: ("New secret…", { SecretDialogs.openNew(admin) }),
            retry: { Task { await model.reload() } }
        ) {
            VStack(alignment: .leading, spacing: Space.s5) {
                modeNote(model.mode)
                AdminNoticeBanner(notice: admin.host.elevationNotice)
                AdminSection(
                    title: "Secrets",
                    detail:
                        "Name, size, version and owner are metadata. The value is write-only; the blocks show its size, never its content."
                ) {
                    AdminPanel {
                        HStack {
                            Button("New secret…") { SecretDialogs.openNew(admin) }.buttonStyle(.coreProminent)
                                .help("Store a new write-only value")
                            Spacer()
                            GateTag(text: "Needs admin and Touch ID")
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Space.s8 * 8), spacing: Space.s3, alignment: .top)],
                            spacing: Space.s3
                        ) {
                            ForEach(model.items) { s in SecretCard(admin: admin, model: model, secret: s) }
                        }
                    }
                }
            }
        }
        .task { await model.reload() }
        .accessibilityIdentifier("secrets")
    }

    private func modeNote(_ m: Int) -> some View {
        let words = [
            "Off", "Throwaway only", "Real credentials",
        ]
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: m == 0 ? "lock" : "checkmark.shield").foregroundStyle(palette.primary)
                .accessibilityHidden(true)
            (Text("Mode \(m)\(words.indices.contains(m) ? ". \(words[m])" : ""). ").bold()
                + Text(
                    m == 0
                        ? "New values and leases are refused until an admin raises the mode in Feature switches."
                        : "Use throwaway values only. A value that looks like a real key is refused."
                ))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.glassCard, in: coreShape(Radius.cardMac))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("secrets-mode")
    }
}

private struct SecretCard: View {
    let admin: AdminModel
    let model: SecretsModel
    let secret: SecretItem
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(secret.name).font(.system(size: MacTextSize.headline, weight: .semibold, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle).help(secret.name)
                Spacer(minLength: Space.s2)
                Text(secret.owner).font(.system(size: MacTextSize.meta, design: .monospaced))
                    .foregroundStyle(palette.text2).lineLimit(1).help("The device that stored it")
            }
            HStack(spacing: Space.s2) {
                Image(systemName: "lock").foregroundStyle(palette.text2).accessibilityHidden(true)
                SizeBlocks(size: secret.size)
                Spacer(minLength: 0)
                Text(AdminWords.bytes(secret.size)).font(.system(size: MacTextSize.body, design: .monospaced))
            }
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.controlMd)
            .background(palette.uDim, in: coreShape(Radius.control))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Value, \(secret.size) bytes, hidden")
            fact("Version") {
                HStack(spacing: Space.s2) {
                    HStack(spacing: Space.s1) {
                        ForEach(0..<Int(min(max(secret.version, 1), 5)), id: \.self) { i in
                            coreShape(1).fill(
                                i == Int(min(max(secret.version, 1), 5)) - 1 ? palette.primary : palette.track
                            )
                            .frame(width: Space.s2, height: Space.s2)
                        }
                    }
                    .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Text("v\(secret.version)").font(.system(size: MacTextSize.body, design: .monospaced))
                }
            }
            fact("Delivery") {
                HStack(spacing: Space.s1) {
                    ForEach(["env", "file", "askpass"], id: \.self) { d in Pick(text: d, on: d == secret.delivery) }
                    if !["env", "file", "askpass"].contains(secret.delivery) { Pick(text: secret.delivery, on: true) }
                }
            }
            fact("Runners") {
                if secret.runners.isEmpty {
                    Text("none").foregroundStyle(palette.text2)
                } else {
                    HStack(spacing: Space.s1) {
                        ForEach(secret.runners, id: \.self) { MetaChip(text: model.runnerName($0)) }
                    }
                }
            }
            fact("key_id") { Text(secret.keyID).font(.system(size: MacTextSize.body, design: .monospaced)) }
            if let lease = model.leases.first(where: { $0.secret == secret.name }) { LeaseLine(lease: lease) }
            if let e = model.rowError[secret.name] { IssueLine(code: nil, text: e) }
            HStack(spacing: Space.s4) {
                AdminLink(title: "Replace value", help: "Store a new value for \(secret.name); the version goes up") {
                    SecretDialogs.openReplace(admin, secret)
                }
                .accessibilityLabel("Replace the value of \(secret.name)")
                AdminLink(title: "Lease…", help: "Hand \(secret.name) to a runner for a short time") {
                    SecretDialogs.openLease(admin, secret)
                }
                .accessibilityLabel("Lease \(secret.name)")
                AdminLink(title: "Delete", danger: true, help: "Delete \(secret.name); this cannot be undone") {
                    SecretDialogs.openDelete(admin, secret)
                }
                .accessibilityLabel("Delete \(secret.name)")
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.uDim.opacity(0.6), in: coreShape(Radius.cardMac))
        .contextMenu {
            Button("Replace value…") { SecretDialogs.openReplace(admin, secret) }
            Button("Lease…") { SecretDialogs.openLease(admin, secret) }
            Button("Delete…") { SecretDialogs.openDelete(admin, secret) }
            Button("Copy name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(secret.name, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("secret-\(secret.name)")
    }

    private func fact<V: View>(_ title: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text(title).foregroundStyle(palette.text2).frame(width: Space.s8 * 2, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .font(.system(size: MacTextSize.body))
        .accessibilityElement(children: .combine)
    }
}

/// A delivery option, the one that holds drawn with a border and a bold word (never colour alone).
private struct Pick: View {
    let text: String
    let on: Bool
    @Environment(\.corePalette) private var palette
    var body: some View {
        Text(text).font(.system(size: MacTextSize.meta, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? palette.text : palette.text2)
            .padding(.horizontal, Space.s2).frame(minHeight: MacSize.chip)
            .background(on ? palette.navActive : palette.uDim, in: coreShape(Radius.chip))
            .overlay { if on { coreShape(Radius.chip).strokeBorder(palette.navActiveEdge, lineWidth: 1) } }
            .accessibilityLabel("\(text)\(on ? ", current" : "")")
    }
}

/// The size of a value as blocks, one per four bytes: its length, never its content.
private struct SizeBlocks: View {
    let size: Int64
    @Environment(\.corePalette) private var palette
    var body: some View {
        let n = Int(min(max((size + 3) / 4, 1), 14))
        HStack(spacing: Space.s1 / 2) {
            ForEach(0..<n, id: \.self) { _ in
                coreShape(1).fill(palette.text2.opacity(0.55)).frame(width: Space.s2, height: Space.s3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A lease from this Mac: where, and the time left as a bar and a number.
private struct LeaseLine: View {
    let lease: LeaseItem
    @Environment(\.corePalette) private var palette
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let total = max(lease.expiresAt.timeIntervalSince(lease.grantedAt), 1)
            let left = max(lease.expiresAt.timeIntervalSince(ctx.date), 0)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Leased from this Mac").font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                HStack(spacing: Space.s2) {
                    Text(lease.runner).font(.system(size: MacTextSize.body))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            coreShape(Space.s1 / 2).fill(palette.track)
                            coreShape(Space.s1 / 2).fill(palette.primary).frame(width: g.size.width * left / total)
                        }
                    }
                    .frame(height: Space.s1)
                    if left > 0 {
                        Text("\(Int(left.rounded(.up))) s").font(.system(size: MacTextSize.body, design: .monospaced))
                    } else {
                        StateBadge("Expired", tone: .queue, symbol: "xmark.circle")
                    }
                }
                Text(lease.lease).font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(
                    palette.text2
                )
                .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Leased to \(lease.runner), \(left > 0 ? "\(Int(left.rounded(.up))) seconds left" : "expired")")
        }
    }
}

extension SecretsModel {
    func runnerName(_ id: String) -> String { runners.first { $0.id == id }?.name ?? id }
}
