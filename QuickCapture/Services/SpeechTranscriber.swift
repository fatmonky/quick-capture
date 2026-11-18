import AVFoundation
import Observation
import Speech

/// Live, on-device speech-to-text from the microphone.
///
/// Recognition tasks end on their own after long pauses or about a minute of audio,
/// so while recording, each finished task's text is kept and a fresh task is started.
/// Within a task, the recognizer can also start a new utterance after a pause: its
/// results then hold only the new words, so the earlier text is kept before moving on.
@MainActor
@Observable
final class SpeechTranscriber {
    enum Authorization: Equatable {
        case authorized
        case denied(String)
    }

    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer()
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let requestBox = AudioRequestBox()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var taskStartedAt = Date.distantPast
    @ObservationIgnored private var rapidFailures = 0
    @ObservationIgnored private var segments: [String] = []
    @ObservationIgnored private var partial = ""
    @ObservationIgnored private var partialEndedUtterance = false

    /// Joins finished segments and the in-progress partial result into one transcript.
    nonisolated static func combine(_ segments: [String], partial: String) -> String {
        (segments + [partial])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Whether `next` is a revision of the in-progress `previous` result, rather than
    /// the start of a new utterance (which means `previous` must be kept).
    nonisolated static func isRevision(of previous: String, by next: String,
                                       previousEndedUtterance: Bool) -> Bool {
        let old = words(previous), new = words(next)
        guard !old.isEmpty else { return true }
        if new.starts(with: old) { return true }
        if previousEndedUtterance { return false }
        // The recognizer often rewords a result as it hears more, but keeps its
        // opening. A longer result followed by one that starts differently is a reset.
        return old.first == new.first || old.count < 3
    }

    private nonisolated static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    func requestAuthorization() async -> Authorization {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            return .denied("Speech recognition is turned off for Quick Capture. You can turn it on in Settings.")
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            return .denied("Microphone access is turned off for Quick Capture. You can turn it on in Settings.")
        }
        return .authorized
    }

    /// Starts listening. Text recognized from now on is added after `existing`.
    func start(continuing existing: String = "") {
        guard !isRecording else { return }
        errorMessage = nil
        segments = existing.isEmpty ? [] : [existing]
        partial = ""
        updateTranscript()

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw TranscriberError.noMicrophone
            }
            let box = requestBox
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                box.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            teardownAudio()
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            return
        }

        isRecording = true
        rapidFailures = 0
        startRecognitionTask(with: recognizer)
    }

    /// Stops listening, keeping whatever has been recognized so far.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        commitPartial()
        teardownAudio()
        task?.cancel()
        task = nil
    }

    // MARK: - Recognition

    private func startRecognitionTask(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        requestBox.request = request
        taskStartedAt = .now

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let endsUtterance = result?.speechRecognitionMetadata != nil
            let failed = error != nil
            Task { @MainActor in
                self?.handle(text: text, isFinal: isFinal, endsUtterance: endsUtterance,
                             failed: failed, from: request)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, endsUtterance: Bool, failed: Bool,
                        from request: SFSpeechAudioBufferRecognitionRequest) {
        // Ignore late callbacks from a task we've already moved on from.
        guard isRecording, request === requestBox.request else { return }

        if let text {
            if !Self.isRevision(of: partial, by: text, previousEndedUtterance: partialEndedUtterance) {
                commitPartial()
            }
            partial = text
            partialEndedUtterance = endsUtterance
            updateTranscript()
        }
        guard isFinal || failed else { return }

        // A task that fails straight after starting means something is wrong
        // (not just a pause); give up rather than restarting in a tight loop.
        if failed && Date.now.timeIntervalSince(taskStartedAt) < 1 {
            rapidFailures += 1
        } else {
            rapidFailures = 0
        }
        if rapidFailures > 3 {
            errorMessage = "Speech recognition stopped unexpectedly."
            stop()
            return
        }

        commitPartial()
        request.endAudio()
        if let recognizer {
            startRecognitionTask(with: recognizer)
        }
    }

    private func commitPartial() {
        if !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(partial)
        }
        partial = ""
        partialEndedUtterance = false
        updateTranscript()
    }

    private func updateTranscript() {
        transcript = Self.combine(segments, partial: partial)
    }

    private func teardownAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        requestBox.request?.endAudio()
        requestBox.request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum TranscriberError: LocalizedError {
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone is available."
        }
    }
}

/// Hands audio buffers from the real-time audio thread to the current recognition request.
private final class AudioRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
