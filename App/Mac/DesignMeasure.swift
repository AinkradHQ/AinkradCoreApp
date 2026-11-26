#if DEBUG
import AppKit
import Design
import DesignCanvas
import Pairing

/// Debug only. `CORE_DESIGN_SCENE=<scene dir> CORE_DESIGN_MEASURE=<out dir>`: opens a design on the scene inside the real
/// app and drives the canvas through the gesture paths (pan at three zooms, pinch zoom in and out, a drag, then idle) at
/// 120 input steps a second, then writes `summary.txt` and `frames.csv` (T5 frame report) and quits.
/// Frame cost = display-link tick to GPU done (CPU + GPU of one frame); drag latency = input to GPU done of the frame
/// that shows it.
@MainActor
enum DesignMeasure {
    static var view: DesignCanvasNSView?

    static func ready(_ v: DesignCanvasNSView) { view = v }

    static func run(_ app: AppModel, dir: String) async {
        try? await Task.sleep(for: .seconds(3))
        await app.debugDesignDemo().show("open-design")
        for _ in 0..<50 where view == nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard let v = view else { return finish("no canvas: is CORE_DESIGN_SCENE set?") }
        try? await Task.sleep(for: .seconds(2))  // content, assets, first frames, shader warm-up
        v.measureFit()
        try? await Task.sleep(for: .seconds(1))
        _ = v.frameLog.take()
        _ = v.frameLog.takePresented()
        let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        var report: [(String, [FrameLog.Row], [Double])] = []

        func phase(_ name: String, secs: Double, setup: () async -> Void = {}, step: (Double, Double) -> Void) async {
            await setup()
            try? await Task.sleep(for: .milliseconds(300))
            _ = v.frameLog.take()
            _ = v.frameLog.takePresented()
            v.measurePhase(name)
            let t0 = CACurrentMediaTime()
            var last = t0
            while CACurrentMediaTime() - t0 < secs {
                try? await Task.sleep(for: .microseconds(8_333))
                let now = CACurrentMediaTime()
                step(now - t0, now - last)
                last = now
            }
            try? await Task.sleep(for: .milliseconds(200))
            v.measurePhase("")
            report.append((name, v.frameLog.take(), v.frameLog.takePresented()))
        }
        // pan: 2 400 pt/s peak, a figure-of-eight around where the camera is
        for (name, z) in [("pan@fit", 1.0), ("pan@4x", 4.0), ("pan@16x", 16.0)] {
            await phase(
                name, secs: 3,
                setup: {
                    v.measureFit()
                    if z > 1 { v.measureZoom(z, at: c) }
                },
                step: { t, dt in
                    let w = 2 * Double.pi / 3
                    v.measurePan(2400 * cos(w * t) * dt, 1800 * cos(1.7 * w * t) * dt)
                })
            v.measureGestureEnd()
        }
        // pinch: 32x in over 5 s, back out over 5 s, about the centre
        await phase(
            "zoom", secs: 10, setup: { v.measureFit() },
            step: { t, dt in v.measureZoom(exp((t < 5 ? 1 : -1) * log(32) / 5 * dt), at: c) })
        v.measureGestureEnd()
        // drag: press on a node near the centre at 4x, move it on a Lissajous path, release, undo
        var grab = c
        await phase(
            "drag", secs: 5,
            setup: {
                v.measureFit()
                v.measureZoom(4, at: c)
                try? await Task.sleep(for: .milliseconds(200))
                for dy in stride(from: 0.0, through: 200, by: 20) where v.engine.hit(Float(c.x), Float(c.y + dy)) != nil
                {
                    grab = CGPoint(x: c.x, y: c.y + dy)
                    break
                }
                v.measurePointer(down: true, at: grab)
            },
            step: { t, _ in v.measurePointer(at: CGPoint(x: grab.x + 220 * sin(t * 2), y: grab.y + 140 * sin(t * 3.1)))
            })
        v.measurePointer(down: false, at: grab)
        v.measureUndo()
        try? await Task.sleep(for: .milliseconds(500))
        await phase("idle", secs: 3, step: { _, _ in })
        write(report, v: v, dir: dir)
        finish("measured -> \(dir)")
    }

    private static func pct(_ v: [Double], _ p: Double) -> Double {
        guard !v.isEmpty else { return .nan }
        let s = v.sorted()
        return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded(.up)))]
    }

    private static func line(_ name: String, _ v: [Double]) -> String {
        String(
            format: "%@ n=%d p50 %.2f p95 %.2f p99 %.2f max %.2f ms", name, v.count, pct(v, 0.5), pct(v, 0.95),
            pct(v, 0.99), v.max() ?? .nan)
    }

    private static func write(_ report: [(String, [FrameLog.Row], [Double])], v: DesignCanvasNSView, dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let screen = v.window?.screen
        var out = "# Design canvas T5 report (real app, Debug Swift + release engine)\n"
        out += "display: maximumFramesPerSecond \(screen?.maximumFramesPerSecond ?? 0) Hz"
        out += "; Low Power Mode \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")"
        out +=
            "; backing scale \(v.window?.backingScaleFactor ?? 0); view \(Int(v.bounds.width))x\(Int(v.bounds.height)) pt\n"
        out += "budget 8.33 ms (120 Hz)\n\n"
        var csv = "phase,cpu_ms,total_ms,input_to_done_ms\n"
        var panZoom: [Double] = []
        for (name, rows, presented) in report {
            let total = rows.map(\.totalMs)
            let intervals = zip(presented.dropFirst(), presented).map { ($0 - $1) * 1e3 }.filter { $0 < 100 }
            out += "\(name): frames \(rows.count)\n"
            out += "  " + line("frame cost (tick to GPU done)", total) + "\n"
            out += "  " + line("cpu (tick to commit)", rows.map(\.cpuMs)) + "\n"
            out += "  " + line("present interval", intervals) + "\n"
            let lat = rows.flatMap(\.inputToDoneMs)
            if name == "drag" { out += "  " + line("input to GPU done", lat) + "\n" }
            if name.hasPrefix("pan") || name == "zoom" { panZoom += total }
            for r in rows {
                csv += "\(name),\(String(format: "%.3f,%.3f", r.cpuMs, r.totalMs)),"
                csv += r.inputToDoneMs.map { String(format: "%.3f", $0) }.joined(separator: " ") + "\n"
            }
        }
        out += "\n" + line("PAN+ZOOM frame cost", panZoom) + "\n"
        out += String(
            format: "over budget: %.2f%%\n",
            100 * Double(panZoom.filter { $0 > 8.33 }.count) / Double(max(1, panZoom.count)))
        try? out.write(toFile: "\(dir)/summary.txt", atomically: true, encoding: .utf8)
        try? csv.write(toFile: "\(dir)/frames.csv", atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data(out.utf8))
    }

    private static func finish(_ s: String) {
        FileHandle.standardError.write(Data("MEASURE \(s)\n".utf8))
        NSApp.terminate(nil)
    }
}
#endif
