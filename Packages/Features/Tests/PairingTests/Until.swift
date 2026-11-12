import Foundation

/// Waits until a condition holds, polling the main actor; false only after `timeout`.
/// Use `#expect(await until { ... })` instead of a fixed sleep: it returns as soon as the work is done, and a slow machine only costs time, never a false failure.
@MainActor func until(timeout: Duration = .seconds(15), _ ok: @MainActor () -> Bool) async -> Bool {
    let end = ContinuousClock.now + timeout
    while !ok(), ContinuousClock.now < end { try? await Task.sleep(for: .milliseconds(2)) }
    return ok()
}
