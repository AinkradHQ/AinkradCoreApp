import CoreKit
import Foundation
import Shell

/// Hardware (E15 §10): what `/hardware`, `/hardware/pool` and `/jobs` say, kept beside the runners, and fed to the shell's
/// `HardwareDeck` for the top bar and the "Ran on" chips. All of it waits for API minor 95 and a 200 from `/hardware`.
extension TerminalsModel {
    func facts(_ id: String) -> HardwareFacts? { hardware[id].map(HardwareFacts.init) }

    /// Remote runners no longer open terminals (the Core and This Mac do): hides their terminal rows and switch.
    func hidesTerminals(_ r: RunnerItem) -> Bool {
        hardwareOn && !r.builtIn && r.id != host.thisMacRunnerID
    }

    /// One look at the hardware, the pool and the recent jobs. Never throws: a Core without them just shows no hardware.
    func refreshHardware() async {
        guard !hardwareBusy else { return }
        hardwareBusy = true
        defer { hardwareBusy = false }
        guard let list = await service.hardware() else {
            hardwareOn = false
            syncDeck()
            return
        }
        hardware = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for h in list where h.online {
            var s = cpuSamples[h.id] ?? []
            s.append(Double(h.cpuPct))
            if s.count > 60 { s.removeFirst(s.count - 60) }
            cpuSamples[h.id] = s
        }
        pool = await service.hardwarePool()
        jobs = await service.jobs()
        hardwareOn = true
        syncDeck()
    }

    /// The event stream: `hardware.changed` (debounced to 5 s by the Core) and `job.queued|started|ended`.
    func hardwareEvent(kind: String) {
        if kind == "hardware.changed" || kind.hasPrefix("job.") { Task { await refreshHardware() } }
    }

    func syncDeck() {
        let deck = shell.hardwareDeck
        deck.pause = { [weak self] device, span in Task { await self?.pause(device, span) } }
        deck.open = { [weak self] in self?.openMachines() }
        guard hardwareOn else {
            deck.bar = nil
            deck.jobByTerminal = [:]
            deck.jobBySession = [:]
            deck.jobByProject = [:]
            deck.runsBySession = [:]
            deck.offCore = [:]
            return
        }
        let all = Array(hardware.values)
        deck.bar = HardwareDeck.Bar(
            loadPct: pool?.loadPct ?? 0, paused: pool?.paused ?? false, jobs: pool?.jobs ?? 0,
            sessions: pool?.sessions ?? 0,
            macs: all.filter { $0.kind != "core" }.sorted { $0.name < $1.name }
                .map { .init(id: $0.id, name: $0.name, paused: HardwareFacts($0).pausedNow) })
        deck.offCore = Dictionary(
            all.filter { $0.kind != "core" }.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        // `jobs` is newest first: the first of each key is its latest.
        var term: [String: JobPlace] = [:]
        var sess: [String: JobPlace] = [:]
        var proj: [Int: JobPlace] = [:]
        var runs: [String: [HardwareDeck.JobRun]] = [:]
        for j in jobs {
            if let s = j.session, let at = j.startedAt {
                runs[s, default: []].append(.init(startedAt: at, place: j.place))
            }
            if let t = j.terminal, term[t] == nil { term[t] = j.place }
            if let s = j.session, sess[s] == nil { sess[s] = j.place }
            if let p = j.project, proj[p] == nil { proj[p] = j.place }
        }
        deck.jobByTerminal = term
        deck.jobBySession = sess
        deck.jobByProject = proj
        deck.runsBySession = runs
    }

    /// Pauses one machine, or all but the Core, for a span; `.resume` lifts it. Admin: Touch ID once.
    func pause(_ device: String?, _ span: PauseSpan) async {
        let name = device.flatMap { hardware[$0]?.name } ?? "all hardware"
        do {
            try await host.elevated(
                span == .resume ? "Resume \(name)" : "Pause \(name)", done: span == .resume ? "resumed" : "paused"
            ) { try await service.pauseHardware(device, until: span.until()) }
            await refreshHardware()
        } catch is ElevationDeclined {
        } catch {
            let why = CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription
            shell.showToast("Could not \(span == .resume ? "resume" : "pause") \(name). \(why)", kind: .warn)
        }
    }
}
