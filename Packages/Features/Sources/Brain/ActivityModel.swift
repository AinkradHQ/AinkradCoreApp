import Foundation
import Observation
import SwiftUI

public enum ActivityView: String, Sendable, Hashable { case feed, egress }

/// The Activity tab's state. It asks the service for events, filters them for display and keeps one selected row. It stores
/// ids and codes only; the viewing room is the starting filter and "All mounted rooms" is an explicit choice.
@MainActor @Observable
public final class ActivityModel {
    public enum Phase: Equatable {
        case loading, ready
        case failed(String, code: String)
    }

    @ObservationIgnored weak var brain: BrainModel?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var freshTask: Task<Void, Never>?
    @ObservationIgnored private var seenRoom: String?
    @ObservationIgnored private var started = false

    public internal(set) var phase: Phase = .loading
    public private(set) var events: [ActivityEvent] = []
    public private(set) var hasMore = false
    public var filter = ActivityFilter() { didSet { if filter != oldValue { selectedID = nil } } }
    public var view: ActivityView = .feed {
        didSet {
            guard view != oldValue else { return }
            selectedID = nil
            if view == .egress { Task { await loadEgress() } }
        }
    }
    public var selectedID: String?
    public private(set) var egress: [EgressCall] = []
    public private(set) var egressFailed: String?
    public var egressRoom: String? { didSet { if egressRoom != oldValue { Task { await loadEgress() } } } }
    /// Rows that just arrived. They fade in, then settle.
    public private(set) var fresh: Set<String> = []
    /// What a screen reader hears when a row arrives.
    public private(set) var announcement: String?
    @ObservationIgnored let pageSize = 14
    @ObservationIgnored private var limit = 14

    init(brain: BrainModel) { self.brain = brain }

    // MARK: derived

    var mountedIDs: Set<String> { Set(brain?.mountedRooms.map(\.id) ?? []) }
    public var visible: [ActivityEvent] { filter.apply(events, mounted: mountedIDs) }
    public var people: [String] {
        var seen = Set<String>()
        return events.map(\.actor).filter { seen.insert($0).inserted }
    }
    public var selectedEvent: ActivityEvent? { events.first { $0.id == selectedID } }
    public var selectedCall: EgressCall? { egress.first { $0.id == selectedID } }
    /// The room the egress segment shows: its own pick, else the viewing room, else the first mounted one.
    public var egressRoomID: String? {
        let m = brain?.mountedRooms ?? []
        if let id = egressRoom, m.contains(where: { $0.id == id }) { return id }
        if let id = brain?.viewingID, m.contains(where: { $0.id == id }) { return id }
        return m.first?.id
    }
    public var egressRoomSummary: RoomSummary? { brain?.room(egressRoomID) }
    public var isOffline: Bool { brain?.overview?.flags.offlineQueued != nil }

    // MARK: lifecycle

    /// Called when the tab appears or the viewing room changes. A room view starts on its own room.
    public func enter() {
        let viewing = brain?.viewingID
        if seenRoom != viewing {
            seenRoom = viewing
            filter.room = viewing.map { .room($0) } ?? .all
            egressRoom = nil
        }
        if !started {
            started = true
            Task { await load() }
        }
        startLive()
    }

    public func leave() {
        liveTask?.cancel()
        liveTask = nil
    }

    /// Drops everything shown. Called when the Mac locks or the viewing room changes.
    func clear() {
        selectedID = nil
        egress = []
    }

    /// Back to nothing, for a new service or a detached one.
    func reset() {
        leave()
        started = false
        seenRoom = nil
        limit = pageSize
        events = []
        hasMore = false
        egress = []
        egressFailed = nil
        fresh = []
        filter = ActivityFilter()
        view = .feed
        selectedID = nil
        egressRoom = nil
        phase = .loading
    }

    func load() async {
        guard let service = brain?.service else { return }
        phase = .loading
        do {
            let page = try await service.activity(limit: limit)
            events = page.events
            hasMore = page.hasMore
            phase = .ready
        } catch {
            phase = .failed(BrainWords.failure(error), code: (error as? BrainFailure)?.code ?? "audit_unavailable")
        }
        if view == .egress { await loadEgress() }
    }

    public func retry() { Task { await load() } }

    /// Cancel on the error card: keep what this Mac already has and say so.
    public func cancelError() {
        phase = .ready
        brain?.host.shell.showToast("Showing the activity saved on this Mac.", kind: .info)
    }

    public func loadMore() {
        limit += pageSize
        Task { await load() }
    }

    /// Clears what the person set; the room stays on the room picker's pick.
    public func clearFilters() {
        let room = filter.room
        filter = ActivityFilter()
        filter.room = room
    }

    func loadEgress() async {
        guard let service = brain?.service, let id = egressRoomID, brain?.room(id)?.lock == nil else {
            egress = []
            return
        }
        do {
            let list = try await service.egress(room: id)
            guard id == egressRoomID else { return }
            egress = list
            egressFailed = nil
        } catch {
            egress = []
            egressFailed = BrainWords.failure(error)
        }
    }

    private func startLive() {
        guard liveTask == nil, let service = brain?.service else { return }
        liveTask = Task { [weak self] in
            for await e in await service.liveActivity() {
                if Task.isCancelled { break }
                self?.receive(e)
            }
        }
    }

    /// A new row: it goes to the top, fades in and is announced. Nothing else on screen moves.
    func receive(_ e: ActivityEvent) {
        guard !events.contains(where: { $0.id == e.id }) else { return }
        events.insert(e, at: 0)
        fresh.insert(e.id)
        announcement = "New activity: \(e.action)"
        freshTask?.cancel()
        freshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.fresh = [] }
        }
    }
}
