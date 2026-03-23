import AppKit
import Foundation

/// Right-click menu: mana progress (no task log), Show reports, Settings, Quit.
enum ManaMenuBuilder {
    static func buildMenu(
        dataStore: DataStore,
        calendar: Calendar = .current,
        onShowReports: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        let snapshot = dataStore.todayManaSnapshot(calendar: calendar)
        let progressItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        progressItem.view = ManaProgressMenuView(used: snapshot.used, budget: snapshot.budget, remaining: snapshot.remaining)
        progressItem.isEnabled = true
        menu.addItem(progressItem)

        menu.addItem(NSMenuItem.separator())

        let reports = NSMenuItem(title: "Show reports…", action: #selector(MenuActions.showReports), keyEquivalent: "r")
        reports.target = MenuActions.shared
        if let reportsIcon = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Reports") {
            reportsIcon.isTemplate = true
            reports.image = reportsIcon
        }
        menu.addItem(reports)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(MenuActions.openSettings), keyEquivalent: ",")
        settingsItem.target = MenuActions.shared
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit micromana", action: #selector(MenuActions.quitApp), keyEquivalent: "q")
        quit.target = MenuActions.shared
        menu.addItem(quit)

        MenuActions.shared.onShowReports = onShowReports
        MenuActions.shared.onSettings = onSettings
        MenuActions.shared.onQuit = onQuit

        return menu
    }
}

/// Full bar = all mana remaining; fill depletes as time is tracked / recorded. Fill matches `ManaColors` (including under 20% remaining).
private final class RemainingManaBarView: NSView {
    static let barHeight: CGFloat = 10

    private var remainingFraction: CGFloat

    init(remainingFraction: CGFloat) {
        self.remainingFraction = remainingFraction
        super.init(frame: .zero)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r: CGFloat = 4
        let trackBounds = bounds
        let trackPath = NSBezierPath(roundedRect: trackBounds, xRadius: r, yRadius: r)
        NSColor.controlBackgroundColor.setFill()
        trackPath.fill()

        let w = trackBounds.width * remainingFraction
        guard w > 0.5 else { return }

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        let fillRect = NSRect(x: trackBounds.minX, y: trackBounds.minY, width: w, height: trackBounds.height)
        ManaColors.barNS.setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Compact menu-bar row showing remaining mana and consumption progress.
final class ManaProgressMenuView: NSView {
    init(used: TimeInterval, budget: TimeInterval, remaining: TimeInterval) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "mana today")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .labelColor

        let detail = NSTextField(labelWithString: Self.detailString(used: used, budget: budget, remaining: remaining))
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        let remainingFraction: CGFloat
        if budget > 0 {
            remainingFraction = CGFloat(min(1, max(0, remaining / budget)))
        } else {
            remainingFraction = 0
        }
        let progress = RemainingManaBarView(remainingFraction: remainingFraction)
        progress.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, detail, progress])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            progress.widthAnchor.constraint(equalToConstant: 236),
            progress.heightAnchor.constraint(equalToConstant: RemainingManaBarView.barHeight)
        ])
    }

    private static func detailString(used: TimeInterval, budget: TimeInterval, remaining: TimeInterval) -> String {
        let u = ReportGenerator.formatDuration(used)
        let r = ReportGenerator.formatDuration(remaining)
        if budget <= 0 {
            return "Set a daily mana budget in Settings."
        }
        return "\(u) passed, \(r) remaining"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 80)
    }
}

final class MenuActions: NSObject {
    static let shared = MenuActions()

    var onShowReports: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    @objc func showReports() {
        onShowReports?()
    }

    @objc func openSettings() {
        onSettings?()
    }

    @objc func quitApp() {
        onQuit?()
    }
}
