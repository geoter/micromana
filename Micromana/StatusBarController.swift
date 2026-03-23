import AppKit
import Combine
import UniformTypeIdentifiers

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let timeTracker = TimeTracker()
    private let dataStore = DataStore.shared
    private let speech = SpeechToTextService()

    private var taskWindow: TaskEntryWindowController?
    private var settingsWindow: SettingsWindowController?
    private var reportsWindow: ReportsWindowController?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        observeTimeTracker()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let img = Self.statusBarPotionImage(assetName: StatusBarAsset.idle) {
            button.image = img
        } else {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "micromana")
            button.image?.isTemplate = true
        }
        button.toolTip = "Micromana — click to start/stop tracking"
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateAppearance()
    }

    private func observeTimeTracker() {
        timeTracker.$elapsedTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateAppearance() }
            .store(in: &cancellables)
        timeTracker.$isTracking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateAppearance() }
            .store(in: &cancellables)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
            return
        }
        toggleTracking()
    }

    private func toggleTracking() {
        if timeTracker.isTracking {
            guard let range = timeTracker.stop() else { return }
            openTaskWindow(start: range.start, end: range.end)
        } else {
            timeTracker.start()
            updateAppearance()
        }
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        if timeTracker.isTracking {
            if let img = Self.statusBarPotionImage(assetName: StatusBarAsset.recording) {
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "timer.circle.fill", accessibilityDescription: "Tracking")
                button.image?.isTemplate = true
            }
            button.toolTip = "Tracking — \(timeTracker.formattedElapsed())"
        } else {
            if let img = Self.statusBarPotionImage(assetName: StatusBarAsset.idle) {
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "micromana")
                button.image?.isTemplate = true
            }
            button.toolTip = "micromana — click to start tracking"
        }
    }

    private enum StatusBarAsset {
        static let idle = "PotionIdle"
        static let recording = "PotionRecording"
    }

    /// Full-color potion icons from the asset catalog; sized for the menu bar.
    private static func statusBarPotionImage(assetName: String) -> NSImage? {
        guard let source = NSImage(named: assetName) else { return nil }
        let image = (source.copy() as? NSImage) ?? source
        image.isTemplate = false
        let side: CGFloat = 18
        image.size = NSSize(width: side, height: side)
        return image
    }

    private func openTaskWindow(start: Date, end: Date) {
        updateAppearance()
        taskWindow?.close()
        let controller = TaskEntryWindowController(
            startTime: start,
            endTime: end,
            dataStore: dataStore,
            speech: speech,
            onDismiss: { [weak self] in
                self?.taskWindow = nil
            }
        )
        taskWindow = controller
        controller.show()
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        dataStore.load()
        let menu = ManaMenuBuilder.buildMenu(
            dataStore: dataStore,
            onShowReports: { [weak self] in
                self?.openReports()
            },
            onSettings: { [weak self] in
                self?.openSettings()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    private func openReports() {
        reportsWindow?.close()
        let w = ReportsWindowController(
            dataStore: dataStore,
            onExportCSV: { [weak self] day in
                self?.downloadReport(for: day)
            },
            onClose: { [weak self] in
                self?.reportsWindow = nil
            }
        )
        reportsWindow = w
        w.show()
    }

    private func openSettings() {
        settingsWindow?.close()
        let w = SettingsWindowController(dataStore: dataStore)
        settingsWindow = w
        w.show()
    }

    private func downloadReport(for day: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let tasks = dataStore.tasks(on: dayStart, calendar: calendar)
        guard let csvData = ReportGenerator.makeCSVData(tasks: tasks, calendar: calendar) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let df = DateFormatter()
        df.calendar = calendar
        df.timeZone = calendar.timeZone
        df.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "\(df.string(from: dayStart)).csv"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csvData.write(to: url, options: [.atomic])
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not save report"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
