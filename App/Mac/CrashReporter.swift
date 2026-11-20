import CoreKit
import Foundation
import MetricKit
import Shell

/// E12-6 (D-34): crash reports without personal content. Two sources feed one spool (`CrashSpool`):
/// - MetricKit delivers the crash diagnostics of the previous run at the next launch (signals, Mach exceptions);
/// - our own handler writes an uncaught Objective-C exception down at once (name and stack only, never its reason text).
/// The spool is sent at launch and after each delivery, only while "Send crash reports" is on; turning it off discards what
/// was waiting. Frames are `Module+0xOffset`, symbolicated later from our own dSYMs.
final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReporter()

    func start() {
        MXMetricManager.shared.add(self)
        NSSetUncaughtExceptionHandler { e in
            // The reason and userInfo can hold anything (a path, a name): only the class name and the stack are kept.
            let frames = e.callStackReturnAddresses.prefix(100).map { CrashReporter.frame($0.uintValue) }
            CrashSpool.write(CrashReporter.report(kind: e.name.rawValue, frames: frames))
        }
        Task { await CrashSpool.flush(enabled: CrashReportPrefs.isEnabled) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                let frames = CrashReport.frames(fromCallStackTree: c.callStackTree.jsonRepresentation())
                CrashSpool.write(Self.report(kind: "crash", frames: frames))
            }
        }
        Task { await CrashSpool.flush(enabled: CrashReportPrefs.isEnabled) }
    }

    private static func report(kind: String, frames: [String]) -> CrashReport {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let info = Bundle.main.infoDictionary
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return CrashReport(
            version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            os: "macOS \(v.majorVersion).\(v.minorVersion)", arch: arch, kind: kind, frames: frames)
    }

    /// `Module+0xOffset` for a return address: the image it is in and how far into it.
    private static func frame(_ address: UInt) -> String {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0, let base = info.dli_fbase,
            let name = info.dli_fname
        else { return "unknown+0x\(String(address, radix: 16))" }
        let module = (String(cString: name) as NSString).lastPathComponent
        return "\(module)+0x\(String(address - UInt(bitPattern: base), radix: 16))"
    }
}
