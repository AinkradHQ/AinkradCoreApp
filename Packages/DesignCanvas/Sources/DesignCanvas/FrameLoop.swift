import DesignEngine
import Foundation
import Metal
import QuartzCore
import os

/// The render thread (T4): a `CAMetalDisplayLink` at the display's rate on its own run loop. Each vsync it advances the
/// engine's animations (`de_tick`: the rubber-band settle) and the pinch momentum, and draws only when the engine says
/// something changed (`de_needs_frame`), so an idle canvas draws nothing; when nothing moves either, the link pauses until
/// input wakes it. The main thread never draws; it only feeds input into the engine and calls `wake()`.
///
/// `@unchecked Sendable`: the mutable state is either touched only on the render thread (`link`, `last`) or guarded by
/// `state` (an unfair lock); the Metal objects are thread-safe by Metal's contract.
final class FrameLoop: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    let engine: Engine
    let queue: any MTLCommandQueue
    let log = FrameLog()

    struct Shared {
        /// Pinch momentum: zoom rate (log scale per second) and its anchor.
        var zoomRate = 0.0
        var zoomAt = CGPoint.zero
        var reduceMotion = false
        /// Inputs since the last frame (stamp, for the input-to-frame latency of a drag).
        var inputs: [Double] = []
        var phase = ""
    }
    let state = OSAllocatedUnfairLock(initialState: Shared())
    /// Asset hashes the renderer missed, checked at most every 0.25 s after a frame.
    var onMissing: @Sendable ([String]) -> Void = { _ in }

    private var link: CAMetalDisplayLink?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var last = 0.0
    private var lastMissingCheck = 0.0

    init(engine: Engine, queue: any MTLCommandQueue) {
        self.engine = engine
        self.queue = queue
    }

    func start(layer: CAMetalLayer) {
        let ready = DispatchSemaphore(value: 0)
        let box = LayerBox(layer: layer)
        let t = Thread { [self] in
            let l = CAMetalDisplayLink(metalLayer: box.layer)
            l.delegate = self
            l.preferredFrameLatency = 1
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .current, forMode: .default)
            link = l
            runLoop = CFRunLoopGetCurrent()
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "Design canvas render"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        ready.wait()
    }

    func stop() {
        perform { [self] in
            link?.invalidate()
            link = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    /// Something changed (input, sync, an asset, a resize): unpause; the next vsync draws.
    func wake(input: Bool = false) {
        if input { state.withLock { $0.inputs.append(CACurrentMediaTime()) } }
        perform { [self] in link?.isPaused = false }
    }

    private func perform(_ block: @escaping @Sendable () -> Void) {
        guard let rl = runLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    // MARK: render thread

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let t0 = CACurrentMediaTime()
        let dt = last > 0 ? min(max(t0 - last, 1.0 / 240), 0.1) : 1.0 / 120
        last = t0
        let h = engine.h
        var moving = de_tick(h, Float(dt)) == 1
        let (rate, at, reduce) = state.withLock { ($0.zoomRate, $0.zoomAt, $0.reduceMotion) }
        if rate != 0 {
            let next = reduce ? 0 : rate * pow(0.86, dt * 60)
            if abs(next) < 0.05 {
                state.withLock { $0.zoomRate = 0 }
                de_gesture_end(h, reduce ? 1 : 0)
            } else {
                de_magnify(h, Float(exp(next * dt)), Float(at.x), Float(at.y))
                state.withLock { $0.zoomRate = next }
                moving = true
            }
        }
        if de_needs_frame(h) == 1 {
            draw(update.drawable, start: t0)
        } else if !moving {
            last = 0
            link.isPaused = true
        }
        if t0 - lastMissingCheck > 0.25 {
            lastMissingCheck = t0
            let m = engine.missingAssets()
            if !m.isEmpty { onMissing(m) }
        }
    }

    private func draw(_ drawable: any CAMetalDrawable, start: Double) {
        // The engine reads size and format from this drawable's texture, not the layer: during a live resize the layer's
        // drawableSize changes on the main thread while this drawable keeps the size it was made with (#298 fix 5).
        let rc = de_draw_metal(engine.h, Unmanaged.passUnretained(drawable.texture).toOpaque())
        guard rc == DE_OK, let cb = queue.makeCommandBuffer() else { return }
        let encoded = CACurrentMediaTime()
        let (inputs, phase) = state.withLock { s in
            defer { s.inputs = [] }
            return (s.inputs, s.phase)
        }
        let log = log
        let f = FrameLog.Frame(phase: phase, start: start, cpuMs: (encoded - start) * 1e3, inputs: inputs)
        cb.addCompletedHandler { @Sendable _ in log.add(f, done: CACurrentMediaTime()) }
        drawable.addPresentedHandler { @Sendable d in log.presented(f.start, at: d.presentedTime) }
        cb.present(drawable)
        cb.commit()
    }
}

/// Carries the layer to the render thread; `CAMetalLayer`'s drawable and display-link APIs are thread-safe.
private struct LayerBox: @unchecked Sendable { let layer: CAMetalLayer }

/// Frame timings for the T5 report: CPU (tick to commit), total (tick to GPU done) and input to GPU done.
public final class FrameLog: Sendable {
    struct Frame: Sendable {
        let phase: String
        let start: Double
        let cpuMs: Double
        let inputs: [Double]
    }
    public struct Row: Sendable {
        public let phase: String
        public let cpuMs: Double
        public let totalMs: Double
        public let inputToDoneMs: [Double]
    }
    private let rows = OSAllocatedUnfairLock(initialState: [Double: Row]())
    private let presents = OSAllocatedUnfairLock(initialState: [Double]())

    func add(_ f: Frame, done: Double) {
        let r = Row(
            phase: f.phase, cpuMs: f.cpuMs, totalMs: (done - f.start) * 1e3,
            inputToDoneMs: f.inputs.map { (done - $0) * 1e3 })
        rows.withLock { $0[f.start] = r }
    }
    func presented(_ start: Double, at t: Double) { presents.withLock { $0.append(t) } }

    /// On-glass times so far (sorted), and clears them.
    public func takePresented() -> [Double] {
        presents.withLock { p in
            defer { p = [] }
            return p.sorted()
        }
    }

    /// Frames so far, in order, and clears the log.
    public func take() -> [Row] {
        rows.withLock { r in
            defer { r = [:] }
            return r.sorted { $0.key < $1.key }.map(\.value)
        }
    }
}
