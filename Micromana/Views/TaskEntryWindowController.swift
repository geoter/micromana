import AppKit
import SwiftUI

final class TaskEntryWindowController: NSWindowController, NSWindowDelegate {
    private let speech: SpeechToTextService
    private let onDismiss: () -> Void

    init(
        startTime: Date,
        endTime: Date,
        dataStore: DataStore,
        speech: SpeechToTextService,
        onDismiss: @escaping () -> Void
    ) {
        self.speech = speech
        self.onDismiss = onDismiss

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "micromana — Task"
        window.isReleasedWhenClosed = false
        window.level = .floating

        super.init(window: window)
        window.delegate = self

        let view = TaskEntryView(
            startTime: startTime,
            endTime: endTime,
            onSave: { [weak self] description in
                let entry = TaskEntry(startTime: startTime, endTime: endTime, description: description)
                dataStore.addTask(entry)
                self?.window?.close()
            },
            onDiscard: { [weak self] in
                self?.window?.close()
            },
            speech: speech,
            dataStore: dataStore
        )

        let host = NSHostingController(rootView: view)
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

    func windowWillClose(_ notification: Notification) {
        speech.cancelRecording()
        onDismiss()
    }
}
