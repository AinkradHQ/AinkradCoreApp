import Foundation

/// A failure that may pass by itself: the Core did not answer, or answered 5xx. A 4xx is never one (the same call would
/// be refused again). `BrainHTTPError` and `CoreError` say so in the modules that know them.
public protocol TransientFailure: Error { var isTransient: Bool { get } }

/// The one retry policy of an import: forever, with a capped pause (1 s up to 30 s), on transient failures only.
public enum ImportRetry {
    public static func isTransient(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        if let t = error as? any TransientFailure { return t.isTransient }
        return error is URLError
    }

    /// 1, 2, 4, 8, 16, 30, 30 ... seconds for attempt 1, 2, 3 ...
    public static func seconds(attempt: Int) -> Double { Double(min(30, 1 << min(max(attempt - 1, 0), 5))) }

    public static let pause: @Sendable (Int) async -> Void = {
        try? await Task.sleep(for: .seconds(seconds(attempt: $0)))
    }

    /// Runs `op` until it works or fails for good. `waiting(true)` is said at each transient failure, `waiting(false)`
    /// once the call works again (or fails for good), so the screen can show "waiting for your Core" meanwhile.
    public static func run<T>(
        isolation: isolated (any Actor)? = #isolation, pause: (Int) async -> Void, waiting: (Bool) async -> Void,
        _ op: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                let v = try await op()
                if attempt > 0 { await waiting(false) }
                return v
            } catch {
                guard isTransient(error) else {
                    if attempt > 0 { await waiting(false) }
                    throw error
                }
                attempt += 1
                await waiting(true)
                try Task.checkCancellation()
                await pause(attempt)
            }
        }
    }
}
