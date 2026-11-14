import Foundation
import Testing

@testable import Admin

struct CodeModeAuditTests {
    private func row(_ action: String, _ details: String) -> AuditItem {
        AuditItem(
            seq: 1, at: Date(), action: action, actor: .user(1), entityKind: nil, entityRef: nil, details: details,
            origin: AuditOrigin(kind: "ai_session", reference: nil, rootKind: "person", rootReference: "d_ph18x3Kz"))
    }

    @Test func aCodeModeCallReadsAsASentence() {
        let ok = CodeModeAudit.sentence(
            row("code_mode.call", #"{"op":"brainAiSearch","outcome":"ok","project":"portal"}"#))
        #expect(ok?.who == "An AI session in portal" && ok?.verb == "searched" && ok?.what == "the Brain")
        let no = CodeModeAudit.sentence(
            row("code_mode.call", #"{"op":"connections.jira.create_issue","outcome":"denied"}"#))
        #expect(no?.verb == "was refused when it tried to" && no?.what == "create issue with Jira")
    }

    @Test func otherRowsAreLeftToTheGenericSentence() {
        #expect(CodeModeAudit.sentence(row("device.revoked", "{}")) == nil)
        #expect(CodeModeAudit.sentence(row("brain.ai.proposed", "{}"))?.what == "a Brain record")
    }

    @Test func theRootNamesTheDeviceThatStartedIt() {
        let o = AuditOrigin(kind: "ai_session", reference: nil, rootKind: "person", rootReference: "d_ph18x3Kz")
        #expect(
            AuditWords.originSentence(o, deviceName: { $0 == "d_ph18x3Kz" ? "Ahmed's phone" : nil })
                == "An AI session, started by Ahmed's phone")
        #expect(AuditWords.originSentence(o) == "An AI session, started by a person")
    }

    @Test func theArgumentFingerprintIsATechnicalDetail() {
        let r = AuditWords.detailRows(row("code_mode.call", #"{"op":"listAudit","args_sha256":"ab12"}"#))
        #expect(r.plain.map(\.0) == ["operation"] && r.technical.contains { $0.0 == "args sha256" })
    }
}
