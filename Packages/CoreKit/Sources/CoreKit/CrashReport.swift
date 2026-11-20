import Foundation

/// E12-6 (D-34): a crash report with NO personal content, sent to our own server (`POST https://ainkrad.io/api/crash`, the
/// site Worker's `crash.ts`). It carries the app and OS version, the CPU, what kind of crash it was, and a stack of
/// `Module+0xOffset` frames that are symbolicated later from our own dSYMs. No path, no user name, no Core name, no exception
/// text, no device id: nothing in it identifies a person or a machine. The Worker refuses any other field.
public struct CrashReport: Codable, Equatable, Sendable {
    public var app = "Ainkrad"
    public var version: String
    public var os: String
    public var arch: String
    public var kind: String
    public var frames: [String]

    /// What the Worker accepts in a short field (`FIELD` in crash.ts).
    static func clean(_ s: String, fallback: String) -> String {
        let ok = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._+()/:-")
        let t = String(s.filter { ok.contains($0) }.prefix(80))
        return t.isEmpty ? fallback : t
    }

    /// `Module+0xhex`: a module name of `A-Za-z0-9_.-` (at most 64) and a lower-case hex offset (at most 16 digits).
    static func isFrame(_ f: String) -> Bool {
        guard let plus = f.range(of: "+0x") else { return false }
        let module = f[..<plus.lowerBound]
        let off = f[plus.upperBound...]
        return (1...64).contains(module.count)
            && module.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
            && (1...16).contains(off.count)
            && off.allSatisfy { $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }
    }

    public init(version: String, os: String, arch: String, kind: String, frames: [String]) {
        self.version = Self.clean(version, fallback: "unknown")
        self.os = Self.clean(os, fallback: "unknown")
        self.arch = Self.clean(arch, fallback: "unknown")
        // A kind is one word (an exception's class name, `crash`): letters, digits and `_.-` only, as the server insists.
        let word = String(kind.prefix { $0.isLetter || $0.isNumber || "_.-".contains($0) }.prefix(60))
        self.kind = word.isEmpty ? "crash" : word
        // A frame is exactly `Module+0xOffset` (what the server accepts); anything else is dropped, so a path or a user name
        // can never ride along.
        self.frames = frames.filter(Self.isFrame).prefix(200).map { $0 }
    }

    /// The frames of the crashing thread from MetricKit's call stack tree JSON (`MXCallStackTree.jsonRepresentation()`):
    /// `binaryName+0xoffset`, from the top of the stack down. Nothing else in the tree is read.
    public static func frames(fromCallStackTree data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stacks = root["callStacks"] as? [[String: Any]]
        else { return [] }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var out: [String] = []
        var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first
        while let f = frame, out.count < 200 {
            let name = (f["binaryName"] as? String) ?? "unknown"
            let off = (f["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value ?? 0
            out.append("\(name)+0x\(String(off, radix: 16))")
            frame = (f["subFrames"] as? [[String: Any]])?.first
        }
        return out
    }
}

/// Reports waiting to be sent (a crash is written down at once; the next launch sends it when the person allows it).
public enum CrashSpool {
    public static func directory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Ainkrad/crash-reports", isDirectory: true)
    }

    public static func write(_ r: CrashReport, in dir: URL = directory()) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(r) else { return }
        try? data.write(to: dir.appendingPathComponent("\(UUID().uuidString).json"), options: .atomic)
    }

    /// Sends every waiting report (at most 20) and deletes each one the server took or refused. With `enabled` false, they
    /// are deleted unsent: turning the switch off also discards what was waiting.
    public static func flush(
        enabled: Bool, in dir: URL = directory(),
        endpoint: URL = URL(string: "https://ainkrad.io/api/crash")!,
        send: @Sendable (URLRequest) async -> Int = { req in
            let r = try? await URLSession(configuration: .ephemeral).data(for: req)
            return (r?.1 as? HTTPURLResponse)?.statusCode ?? 0
        }
    ) async {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.prefix(20)
        for f in files {
            guard enabled, let body = try? Data(contentsOf: f) else {
                try? FileManager.default.removeItem(at: f)
                continue
            }
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.timeoutInterval = 15
            let status = await send(req)
            // 204 taken; 400/413 refused for good; anything else (offline, 5xx) stays for the next launch.
            if status == 204 || status == 400 || status == 413 { try? FileManager.default.removeItem(at: f) }
        }
    }
}
