#if DEBUG
import BrainImport
import Foundation

/// Debug only: invented sync, sources, rules and search results for the gallery.
extension SampleBrainService {
    public func syncStatus() async throws -> SyncStatusWire {
        SyncStatusWire(sources: sampleSources().map { SyncSourceWire(id: $0.id, kind: $0.kind, enabled: $0.enabled) })
    }

    public func sources() async throws -> [SourceWire] { sampleSources() }

    public func putSource(_ s: SourceWire, enabled: Bool?, cursor: SourceCursor?) async throws -> SourceWire {
        var out = s
        if let enabled { out.enabled = enabled }
        sampleSwitches[s.id] = out.enabled
        return out
    }

    public func syncNow() async throws -> SyncResultWire {
        var r = SyncResultWire()
        r.found = 6
        r.stored = 4
        r.duplicate = 2
        r.routed = [RoutedWire(room: "optimus", sources: 3)]
        r.unsorted = 1
        return r
    }

    public func search(room: String, query: String) async throws -> [SearchHit] {
        [
            SearchHit(
                itemID: "s1", sourceKind: "claude_code", title: "Sample: planning the next release",
                snippet: "we agreed to ship the «\(query)» change before the end of the week")
        ]
    }

    public func rules() async throws -> [RuleWire] {
        [
            RuleWire(id: 1, pattern: "Old project", origin: "seed", locked: true, reason: "A refused project."),
            RuleWire(id: 2, pattern: "**/.env", enabled: sampleRuleOn[2] ?? true, reason: "Secrets are never read."),
        ]
    }

    public func setRule(_ id: Int, enabled: Bool) async throws -> RuleWire {
        sampleRuleOn[id] = enabled
        return try await rules().first { $0.id == id } ?? RuleWire(id: id, pattern: "")
    }

    private func sampleSources() -> [SourceWire] {
        if scenario.m3 {
            return SampleM3.sources.map { src in
                var s = src
                s.enabled = sampleSwitches[s.id] ?? s.enabled
                return s
            }
        }
        return [
            SourceWire(id: "core_transcript", device: "core", kind: "core_transcript"),
            SourceWire(id: "mac_claude_code", device: "Sample Mac", kind: "claude_code"),
        ].map {
            var s = $0
            s.enabled = sampleSwitches[s.id] ?? true
            return s
        }
    }
}
#endif
