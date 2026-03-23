import AppKit
import SwiftUI

final class ReportsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private let daySelection = ReportsDaySelection()

    init(dataStore: DataStore, onExportCSV: @escaping (Date) -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "micromana — Reports"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 400)

        let selection = daySelection
        let root = ReportsView(
            dataStore: dataStore,
            selection: selection,
            onExportCSV: { onExportCSV(selection.selectedDay) }
        )
        let host = NSHostingController(rootView: root)
        super.init(window: window)
        window.delegate = self
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
        onClose()
    }
}
