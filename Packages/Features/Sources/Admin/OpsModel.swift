import Foundation
import Observation

/// One line of the Core's Prometheus text.
struct MetricSample: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let labels: [String: String]
    let value: Double
    var labelText: String { labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") }
}

/// A figure from the metrics, worded: only names the Core sent.
struct MetricTile: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let title: String
    let value: String
    /// The Core's own HELP line.
    let help: String
}

struct AlarmState: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let raised: Bool
}

/// An alarm with the reading it watches and the setting that is its threshold, when the Core names both.
struct AlarmDetail: Identifiable, Equatable {
    var id: String { alarm.name }
    let alarm: AlarmState
    let reading: Double?
    let readingText: String?
    let limit: Double?
    let limitText: String?
    /// The setting that holds the threshold.
    let setting: String?
}

enum PrometheusText {
    /// `# HELP`, `# TYPE` and `name{label="v"} value` lines. A line it does not understand is skipped.
    static func parse(_ text: String) -> (samples: [MetricSample], help: [String: String]) {
        var samples: [MetricSample] = []
        var help: [String: String] = [:]
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# HELP ") {
                let rest = line.dropFirst(7)
                if let sp = rest.firstIndex(of: " ") {
                    help[String(rest[..<sp])] = String(rest[rest.index(after: sp)...])
                }
                continue
            }
            if line.hasPrefix("#") || line.isEmpty { continue }
            var name = line
            var labels: [String: String] = [:]
            var tail = Substring("")
            if let open = line.firstIndex(of: "{"), let close = line.lastIndex(of: "}"), open < close {
                name = String(line[..<open])
                tail = line[line.index(after: close)...]
                for pair in line[line.index(after: open)..<close].split(separator: ",") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    if kv.count == 2 {
                        labels[String(kv[0])] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }
                }
            } else if let sp = line.firstIndex(of: " ") {
                name = String(line[..<sp])
                tail = line[sp...]
            }
            guard let value = Double(tail.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") else {
                continue
            }
            samples.append(MetricSample(id: i, name: name, labels: labels, value: value))
        }
        return (samples, help)
    }
}

/// Settings, Core, Ops: what the Core's metrics say. Nothing is added to it: no health check, no alarm the metrics do not name.
@MainActor @Observable
final class OpsModel {
    private(set) var samples: [MetricSample] = []
    private(set) var help: [String: String] = [:]
    private(set) var raw = ""
    var state: SectionState = .loading
    private(set) var readAt: Date?
    /// Each count-like tile's value as this Mac read it, oldest first. The Core reports the present value only, so a chart is what
    /// was sampled while this screen was open.
    private(set) var history: [String: [Double]] = [:]
    static let charted: Set<String> = [
        "ainkrad_devices_active", "ainkrad_runners", "ainkrad_terminals", "ainkrad_agent_sessions",
        "ainkrad_disk_free_percent",
    ]
    var showRaw = false
    @ObservationIgnored private weak var hub: AdminModel?

    /// The figures worth a tile, in this order, when the Core sends them.
    static let tiles: [(name: String, title: String)] = [
        ("ainkrad_uptime_seconds", "Uptime"), ("ainkrad_devices_active", "Devices"), ("ainkrad_runners", "Runners"),
        ("ainkrad_terminals", "Terminals"), ("ainkrad_agent_sessions", "AI sessions"),
        ("ainkrad_disk_free_percent", "Disk free"), ("ainkrad_db_size_bytes", "Database size"),
        ("ainkrad_backup_age_seconds", "Backup age"), ("ainkrad_certificate_days_left", "Certificate"),
        ("ainkrad_events_head_seq", "Event sequence"), ("ainkrad_audit_head_seq", "Audit sequence"),
    ]

    init(hub: AdminModel) { self.hub = hub }

    func reset() {
        samples = []
        raw = ""
        state = .loading
    }

    func reload() async {
        guard let hub, let service = hub.service else { return }
        if samples.isEmpty { state = .loading }
        do {
            raw = try await service.metrics()
            (samples, help) = PrometheusText.parse(raw)
            readAt = Date()
            for name in Self.charted {
                let rows = samples.filter { $0.name == name && $0.labels.isEmpty }
                guard rows.count == 1 else { continue }
                var list = history[name] ?? []
                list.append(rows[0].value)
                if list.count > 60 { list.removeFirst(list.count - 60) }
                history[name] = list
            }
            state = samples.isEmpty ? .empty : .ready
        } catch { state = hub.state(for: error) }
    }

    #if DEBUG
    /// The demo has one read; a few more so the charts have a line to draw.
    func debugSeedHistory() {
        for s in samples where Self.charted.contains(s.name) && s.labels.isEmpty {
            history[s.name] = (0..<20).map { s.value + Double(($0 * 3) % 5) - 2 }
        }
    }
    #endif

    var alarms: [AlarmState] {
        samples.filter { $0.name == "ainkrad_alarm_active" }.compactMap { s in
            s.labels["alarm"].map { AlarmState(name: $0, raised: s.value >= 1) }
        }
    }

    /// Which reading and which setting each alarm the Core names is about (the Core's own names).
    static let alarmSources: [String: (metric: String, setting: String, scale: Double)] = [
        "backup_age": ("ainkrad_backup_age_seconds", "alarm.backup_max_age_secs", 1),
        "cert_expiry": ("ainkrad_certificate_days_left", "alarm.cert_min_days", 1),
        "disk_free": ("ainkrad_disk_free_percent", "alarm.disk_min_free_pct", 1),
    ]

    func details(_ settings: [SettingItem]) -> [AlarmDetail] {
        alarms.map { a in
            guard let src = Self.alarmSources[a.name], let r = samples.first(where: { $0.name == src.metric }) else {
                return AlarmDetail(alarm: a, reading: nil, readingText: nil, limit: nil, limitText: nil, setting: nil)
            }
            let t = settings.first { $0.key == src.setting }
            let limitText = t.map { x -> String in
                x.unit == "seconds"
                    ? Self.duration(Double(x.value))
                    : "\(x.value.formatted())\(x.unitLabel.isEmpty ? "" : " \(x.unitLabel)")"
            }
            return AlarmDetail(
                alarm: a, reading: r.value, readingText: Self.format(src.metric, r.value),
                limit: t.map { Double($0.value) }, limitText: limitText, setting: t?.key)
        }
    }

    var tiles: [MetricTile] {
        Self.tiles.compactMap { t in
            let rows = samples.filter { $0.name == t.name }
            guard !rows.isEmpty else { return nil }
            let text: String
            if rows.count == 1, rows[0].labels.isEmpty {
                text = Self.format(t.name, rows[0].value)
            } else {
                text = rows.map { r in
                    let l = r.labels.sorted { $0.key < $1.key }.map(\.value).joined(separator: " ")
                    return "\(l) \(Self.format(t.name, r.value))"
                }.joined(separator: " · ")
            }
            return MetricTile(name: t.name, title: t.title, value: text, help: help[t.name] ?? "")
        }
    }

    static func format(_ name: String, _ v: Double) -> String {
        if name.hasSuffix("_bytes") { return ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file) }
        if name.hasSuffix("_percent") { return "\(Int(v.rounded()))%" }
        if name.hasSuffix("_days_left") { return "\(Int(v.rounded())) d left" }
        if name.hasSuffix("_seconds") { return duration(v) }
        return Int64(exactly: v.rounded()).map { $0.formatted() } ?? String(v)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 86_400 { return "\(s / 86_400) d \(s % 86_400 / 3_600) h" }
        if s >= 3_600 { return "\(s / 3_600) h \(s % 3_600 / 60) min" }
        if s >= 60 { return "\(s / 60) min \(s % 60) s" }
        return "\(s) s"
    }
}
