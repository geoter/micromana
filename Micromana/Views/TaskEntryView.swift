import SwiftUI

struct TaskEntryView: View {
    let startTime: Date
    let endTime: Date
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    @ObservedObject var speech: SpeechToTextService
    @ObservedObject var dataStore: DataStore

    @State private var text: String = ""
    @State private var textBeforeVoiceSession: String = ""
    @State private var errorMessage: String?
    @FocusState private var editorFocused: Bool

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }

    /// Duration in minutes for display (under 1 min uses two decimals so short sessions aren’t rounded up).
    private var durationMinutesLabel: String {
        let minutes = endTime.timeIntervalSince(startTime) / 60
        if minutes < 1 {
            return String(format: "%.2f min", minutes)
        }
        let rounded = (minutes * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) < 0.05 {
            return String(format: "%.0f min", rounded)
        }
        return String(format: "%.1f min", rounded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log this session")
                .font(.headline)
            Text("\(timeFormatter.string(from: startTime)) – \(timeFormatter.string(from: endTime)) · \(durationMinutesLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .focused($editorFocused)

            HStack {
                Button {
                    toggleMic()
                } label: {
                    Label(
                        speech.isRecording ? "Stop recording" : "Record voice",
                        systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill"
                    )
                }
                .disabled(speech.isTranscribing)

                if speech.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 4)
                }

                Spacer()

                Button("Discard") {
                    let wasRecording = speech.isRecording
                    speech.cancelRecording()
                    if wasRecording {
                        text = textBeforeVoiceSession
                    }
                    onDiscard()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    speech.cancelRecording()
                    onSave(text)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(speech.isRecording)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 280)
        .onAppear {
            editorFocused = true
        }
        .onChange(of: speech.liveTranscription) { newValue in
            guard speech.isRecording else { return }
            let sep = textBeforeVoiceSession.isEmpty ? "" : "\n"
            text = textBeforeVoiceSession + sep + newValue
        }
        .onExitCommand {
            let wasRecording = speech.isRecording
            speech.cancelRecording()
            if wasRecording {
                text = textBeforeVoiceSession
            }
            onDiscard()
        }
    }

    private func toggleMic() {
        errorMessage = nil
        if speech.isRecording {
            let key = dataStore.settings.elevenLabsAPIKey
            let useElevenLabs = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Task {
                do {
                    let t = try await speech.stopRecordingAndTranscribe(apiKey: key)
                    await MainActor.run {
                        if useElevenLabs {
                            let sep = textBeforeVoiceSession.isEmpty ? "" : "\n"
                            text = textBeforeVoiceSession + sep + t
                        }
                        // Without ElevenLabs, liveTranscription already updated `text` while speaking.
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    }
                }
            }
        } else {
            speech.requestMicrophonePermission { granted in
                guard granted else {
                    errorMessage = "Microphone access denied. Enable it in System Settings → Privacy."
                    return
                }
                Task {
                    do {
                        textBeforeVoiceSession = text
                        try await speech.startRecording(apiKey: dataStore.settings.elevenLabsAPIKey)
                    } catch {
                        await MainActor.run {
                            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}
