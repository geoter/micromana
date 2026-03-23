import Foundation

final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published private(set) var tasks: [TaskEntry] = []
    @Published private(set) var settings: AppSettings = .default

    private let fileManager = FileManager.default
    private let tasksFileName = "tasks.json"
    private let settingsFileName = "settings.json"

    /// Folder where `tasks.json` is read and written (default Application Support or a user-chosen location).
    private var resolvedTasksDirectoryURL: URL!

    private var securityScopedLogDirectoryURL: URL?

    private var supportDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("micromana", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private var tasksURL: URL { resolvedTasksDirectoryURL.appendingPathComponent(tasksFileName) }
    private var settingsURL: URL { supportDirectoryURL.appendingPathComponent(settingsFileName) }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        load()
    }

    /// Path shown in Settings for the session log folder (`tasks.json`).
    func logDirectoryPathForDisplay() -> String {
        if let bookmark = settings.logDirectoryBookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale {
                return url.path
            }
        }
        return supportDirectoryURL.path
    }

    func defaultLogDirectoryPathForDisplay() -> String {
        supportDirectoryURL.path
    }

    func load() {
        if fileManager.fileExists(atPath: settingsURL.path),
           let data = try? Data(contentsOf: settingsURL),
           let decoded = try? decoder.decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        refreshLogDirectoryAccess()
        loadTasksFromDisk()
    }

    private func loadTasksFromDisk() {
        if fileManager.fileExists(atPath: tasksURL.path),
           let data = try? Data(contentsOf: tasksURL),
           let decoded = try? decoder.decode([TaskEntry].self, from: data) {
            tasks = decoded.sorted { $0.endTime > $1.endTime }
        } else {
            tasks = []
        }
    }

    private func refreshLogDirectoryAccess() {
        stopLogDirectoryAccess()
        if let bookmark = settings.logDirectoryBookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale, url.startAccessingSecurityScopedResource() {
                securityScopedLogDirectoryURL = url
                resolvedTasksDirectoryURL = url
                if !fileManager.fileExists(atPath: url.path) {
                    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                }
                return
            }
        }
        resolvedTasksDirectoryURL = supportDirectoryURL
    }

    private func stopLogDirectoryAccess() {
        if let url = securityScopedLogDirectoryURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedLogDirectoryURL = nil
        }
    }

    /// Release security-scoped access before the app terminates.
    func prepareForTermination() {
        stopLogDirectoryAccess()
    }

    func saveTasks() {
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: tasksURL, options: [.atomic])
    }

    func saveSettings() {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: [.atomic])
    }

    func addTask(_ entry: TaskEntry) {
        tasks.insert(entry, at: 0)
        saveTasks()
    }

    func updateSettings(_ newSettings: AppSettings) {
        stopLogDirectoryAccess()
        let previousTasks = tasks
        settings = newSettings
        saveSettings()
        refreshLogDirectoryAccess()
        if fileManager.fileExists(atPath: tasksURL.path),
           let data = try? Data(contentsOf: tasksURL),
           let decoded = try? decoder.decode([TaskEntry].self, from: data) {
            tasks = decoded.sorted { $0.endTime > $1.endTime }
        } else {
            tasks = previousTasks
            saveTasks()
        }
    }

    /// Tasks whose `endTime` falls on the given calendar day in `calendar` / `timeZone`.
    func tasks(on day: Date, calendar: Calendar = .current) -> [TaskEntry] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return tasks.filter { $0.endTime >= start && $0.endTime < end }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Distinct calendar days (start of day) that have at least one task, newest first.
    func daysWithTasks(calendar: Calendar = .current) -> [Date] {
        var seen = Set<Date>()
        var result: [Date] = []
        for task in tasks.sorted(by: { $0.endTime > $1.endTime }) {
            let day = calendar.startOfDay(for: task.endTime)
            if seen.insert(day).inserted {
                result.append(day)
            }
        }
        return result
    }

    func totalDuration(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        tasks(on: day, calendar: calendar).reduce(0) { $0 + $1.duration }
    }

    /// Days with tasks, oldest first (for charts).
    func daysWithTasksAscending(calendar: Calendar = .current) -> [Date] {
        daysWithTasks(calendar: calendar).sorted(by: <)
    }

    /// Up to `maxDays` recent days that have tasks, with consumed vs budget (for reports chart).
    func dailyManaChartPoints(calendar: Calendar = .current, maxDays: Int = 30) -> [DailyManaPoint] {
        let budget = TimeInterval(settings.dailyManaMinutes * 60)
        let days = daysWithTasksAscending(calendar: calendar)
        let tail = Array(days.suffix(maxDays))
        let df = DateFormatter()
        df.dateFormat = "EEE M/d"
        df.calendar = calendar
        df.timeZone = calendar.timeZone
        return tail.map { day in
            DailyManaPoint(
                id: day,
                day: day,
                shortLabel: df.string(from: day),
                consumed: totalDuration(on: day, calendar: calendar),
                budget: budget
            )
        }
    }

    /// Today’s consumed time and mana budget (calendar day).
    func todayManaSnapshot(calendar: Calendar = .current) -> (used: TimeInterval, budget: TimeInterval, remaining: TimeInterval) {
        let day = calendar.startOfDay(for: Date())
        let budget = TimeInterval(settings.dailyManaMinutes * 60)
        let used = totalDuration(on: day, calendar: calendar)
        let remaining = max(0, budget - used)
        return (used, budget, remaining)
    }
}

