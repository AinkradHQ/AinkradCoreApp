import AVFoundation
import Foundation
import Observation
import Speech

/// Voice dictation for the composer, on this Mac: macOS speech recognition with `requiresOnDeviceRecognition`, so audio never
/// leaves the machine. The two permissions (microphone, speech recognition) are asked for the first time you press the mic,
/// never before. Where on-device recognition is not available for the language, the mic is hidden rather than sending audio out.
@MainActor @Observable
final class Dictation {
    enum State: Equatable {
        case idle
        case listening
        /// Why it cannot listen: the person said no, or the Mac has no input.
        case blocked(String)
    }

    private(set) var state: State = .idle
    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Whether this Mac can recognise speech on its own: if not, the composer shows no mic.
    static var available: Bool {
        guard let r = SFSpeechRecognizer(locale: .current) else { return false }
        return r.isAvailable && r.supportsOnDeviceRecognition
    }

    /// Starts listening, or stops when it already does. `update` gets the whole phrase so far each time it changes.
    func toggle(update: @escaping @MainActor (String) -> Void) async {
        if state == .listening {
            stop()
            return
        }
        guard await allowed() else { return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.supportsOnDeviceRecognition else {
            state = .blocked("Speech recognition on this Mac is not available for your language.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            state = .blocked("This Mac has no microphone to listen to.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.feed(Feed(request)))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            state = .blocked("The microphone could not start.")
            return
        }
        self.engine = engine
        self.request = request
        state = .listening
        task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.results { [weak self] text, done in
                Task { @MainActor in
                    if let text { update(text) }
                    if done { self?.stop() }
                }
            })
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        if state == .listening { state = .idle }
    }

    /// Asks the two permissions, once each, the first time. A refusal is remembered by macOS; the composer says where to change it.
    private func allowed() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            state = .blocked(
                "Speech recognition is off for Ainkrad. Turn it on in System Settings, Privacy & Security.")
            return false
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            state = .blocked("The microphone is off for Ainkrad. Turn it on in System Settings, Privacy & Security.")
            return false
        }
        return true
    }

    /// Carries the request to the audio thread: the buffers are appended there, so this must not be main-actor code.
    private final class Feed: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ r: SFSpeechAudioBufferRecognitionRequest) { request = r }
    }

    private nonisolated static func feed(_ f: Feed) -> AVAudioNodeTapBlock {
        { buffer, _ in f.request.append(buffer) }
    }

    private nonisolated static func results(_ report: @escaping @Sendable (String?, Bool) -> Void)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
    {
        { result, error in report(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil) }
    }
}
