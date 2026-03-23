import AVFoundation
import Foundation
import Speech

enum SpeechToTextError: LocalizedError {
    case recordingFailed(String)
    case networkError(String)
    case invalidResponse
    case apiError(String)
    case speechRecognitionDenied
    case speechRecognitionUnavailable

    var errorDescription: String? {
        switch self {
        case .recordingFailed(let msg):
            return "Recording failed: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidResponse:
            return "Could not read transcription response."
        case .apiError(let msg):
            return msg
        case .speechRecognitionDenied:
            return "Speech recognition is off. Enable it in System Settings → Privacy & Security → Speech Recognition."
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this Mac."
        }
    }
}

final class SpeechToTextService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    /// Partial / live transcript for the current recording session.
    @Published private(set) var liveTranscription: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingURL: URL?
    private var audioFile: AVAudioFile?

    /// Resumed when macOS speech reports `isFinal` after stopping, or by timeout.
    private var macFinalWaitContinuation: CheckedContinuation<String, Never>?

    private static let apiURL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

    private func publishOnMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }

    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Starts live transcription from the microphone. Call `stopRecordingAndTranscribe` to finish.
    func startRecording(apiKey: String) async throws {
        guard !isRecording else { return }

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            throw SpeechToTextError.speechRecognitionDenied
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw SpeechToTextError.speechRecognitionUnavailable
        }

        publishOnMain {
            self.liveTranscription = ""
        }
        macFinalWaitContinuation = nil

        let useElevenLabs = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if useElevenLabs {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("micromana-stt-\(UUID().uuidString).caf")
            recordingURL = url
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if error != nil {
                return
            }
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            self.publishOnMain {
                self.liveTranscription = text
            }
            if result.isFinal {
                if let cont = self.macFinalWaitContinuation {
                    self.macFinalWaitContinuation = nil
                    cont.resume(returning: text)
                }
            }
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        if useElevenLabs, let url = recordingURL {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            try? self.audioFile?.write(from: buffer)
        }

        audioEngine = engine
        await MainActor.run {
            self.isRecording = true
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            audioEngine = nil
            recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            audioFile = nil
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
                recordingURL = nil
            }
            await MainActor.run {
                self.isRecording = false
            }
            throw SpeechToTextError.recordingFailed(error.localizedDescription)
        }
    }

    func stopRecordingAndTranscribe(apiKey: String) async throws -> String {
        guard isRecording else {
            throw SpeechToTextError.recordingFailed("Not recording.")
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let useElevenLabs = !trimmedKey.isEmpty

        let engine = audioEngine
        let input = engine?.inputNode
        input?.removeTap(onBus: 0)
        engine?.stop()
        audioEngine = nil

        audioFile = nil

        publishOnMain {
            self.isRecording = false
        }

        if useElevenLabs {
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil

            guard let fileURL = recordingURL else {
                throw SpeechToTextError.recordingFailed("No recording file.")
            }
            recordingURL = nil

            publishOnMain {
                self.isTranscribing = true
            }
            defer {
                publishOnMain {
                    self.isTranscribing = false
                }
                try? FileManager.default.removeItem(at: fileURL)
            }

            let data = try Data(contentsOf: fileURL)
            return try await transcribeElevenLabs(audioData: data, fileName: "recording.caf", apiKey: trimmedKey)
        }

        // macOS Speech: register continuation before endAudio so isFinal cannot be missed.
        let transcript = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            self.macFinalWaitContinuation = continuation
            self.recognitionRequest?.endAudio()
            self.recognitionRequest = nil

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let cont = self.macFinalWaitContinuation {
                    self.macFinalWaitContinuation = nil
                    cont.resume(returning: self.liveTranscription)
                }
            }
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        return transcript
    }

    func cancelRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioFile = nil
        macFinalWaitContinuation = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
        publishOnMain {
            self.isRecording = false
            self.liveTranscription = ""
        }
    }

    private func transcribeElevenLabs(audioData: Data, fileName: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        var body = Data()
        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n")
        append("scribe_v2\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: audio/x-caf\r\n\r\n")
        body.append(audioData)
        append("\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language_code\"\r\n\r\n")
        append("en\r\n")

        append("--\(boundary)--\r\n")
        request.httpBody = body

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpeechToTextError.networkError("No HTTP response")
        }
        if http.statusCode != 200 {
            let msg = String(data: respData, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SpeechToTextError.apiError(msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let text = json["text"] as? String else {
            throw SpeechToTextError.invalidResponse
        }
        return text
    }
}
