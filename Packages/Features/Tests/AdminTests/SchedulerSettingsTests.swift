import Testing

@testable import Admin

struct SchedulerSettingsTests {
    private func item(_ key: String, _ unit: String, min: Int64 = 0) -> SettingItem {
        SettingItem(key: key, detail: "", unit: unit, defaultValue: 0, min: min, max: 100_000, value: 0, source: nil)
    }

    @Test func theSchedulerSettingsHaveTheirOwnGroupAndPlainUnits() {
        let wait = item("scheduler.wait_max_secs", "seconds")
        #expect(SettingWords.group(wait).title == "Account switching")
        #expect(SettingWords.value(wait, 600) == "10 min" && SettingWords.value(wait, 90) == "1 min 30 s")
        let rest = item("scheduler.quota_cooldown_secs", "seconds", min: 60)
        #expect(SettingWords.value(rest, 3_600) == "1 h")
        #expect(SettingWords.title(rest) == "An account rests after its quota runs out")
    }

    @Test func zeroHopsReadsAsOffAndTheRateInTenMinutes() {
        let hops = item("scheduler.max_hops", "count")
        #expect(SettingWords.value(hops, 0) == "Off" && SettingWords.value(hops, 1) == "1 switch")
        #expect(SettingWords.value(hops, 3) == "3 switches")
        #expect(SettingWords.value(item("scheduler.failovers_per_10min", "count"), 10) == "10 in 10 min")
    }
}
