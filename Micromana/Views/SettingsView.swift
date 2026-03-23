import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var dataStore: DataStore
    var onClose: () -> Void

    @State private var apiKey: String = ""
    @State private var manaHours: Int = 8
    @State private var manaMinutes: Int = 0
    @State private var logDirectoryBookmarkData: Data?
    @State private var logDirectoryDisplayPath: String = ""

    var body: some View {
        Form {
            Section {
                Text(logDirectoryDisplayPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Choose folder…") {
                        chooseLogDirectory()
                    }
                    Button("Use default location") {
                        logDirectoryBookmarkData = nil
                        logDirectoryDisplayPath = dataStore.defaultLogDirectoryPathForDisplay()
                    }
                    Button("Reveal in Finder") {
                        let path = logDirectoryDisplayPath
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    }
                    .disabled(logDirectoryDisplayPath.isEmpty)
                }
                Text("Session log is stored as tasks.json in this folder. Settings stay in Application Support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Session log")
            }

            Section {
                SecureField("ElevenLabs API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Optional. When set, transcription uses ElevenLabs; otherwise macOS speech recognition is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("ElevenLabs")
            }

            Section {
                Stepper("Hours: \(manaHours)", value: $manaHours, in: 0...24)
                Stepper("Minutes: \(manaMinutes)", value: $manaMinutes, in: 0...59)
                Text("Daily mana budget: \(formattedMana())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("mana (daily time budget)")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 580)
        .onAppear {
            apiKey = dataStore.settings.elevenLabsAPIKey
            let total = dataStore.settings.dailyManaMinutes
            manaHours = total / 60
            manaMinutes = total % 60
            logDirectoryBookmarkData = dataStore.settings.logDirectoryBookmarkData
            logDirectoryDisplayPath = dataStore.logDirectoryPathForDisplay()
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel") {
                    onClose()
                }
                Button("Save") {
                    persist()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)
        }
    }

    private func formattedMana() -> String {
        let m = manaHours * 60 + manaMinutes
        let h = m / 60
        let min = m % 60
        if h > 0 {
            return "\(h)h \(min)m (\(m) minutes total)"
        }
        return "\(min) minutes"
    }

    private func persist() {
        let minutes = max(0, manaHours * 60 + manaMinutes)
        let s = AppSettings(
            elevenLabsAPIKey: apiKey,
            dailyManaMinutes: minutes,
            logDirectoryBookmarkData: logDirectoryBookmarkData
        )
        dataStore.updateSettings(s)
    }

    private func chooseLogDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                DispatchQueue.main.async {
                    logDirectoryBookmarkData = data
                    logDirectoryDisplayPath = url.path
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Could not remember this folder"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}

final class SettingsWindowController: NSWindowController {
    init(dataStore: DataStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "micromana Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 400)

        let root = SettingsView(dataStore: dataStore) { [weak window] in
            window?.close()
        }
        let host = NSHostingController(rootView: root)
        super.init(window: window)
        window.contentViewController = host
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
