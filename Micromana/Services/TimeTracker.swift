import Combine
import Foundation

final class TimeTracker: ObservableObject {
    @Published private(set) var isTracking = false
    @Published private(set) var startTime: Date?
    @Published private(set) var elapsedTime: TimeInterval = 0

    private var ticker: AnyCancellable?

    func start() {
        guard !isTracking else { return }
        let now = Date()
        startTime = now
        elapsedTime = 0
        isTracking = true
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
    }

    /// Stops tracking and returns the interval `(start, end)` if tracking was active.
    func stop() -> (start: Date, end: Date)? {
        guard isTracking, let start = startTime else { return nil }
        ticker?.cancel()
        ticker = nil
        let end = Date()
        isTracking = false
        startTime = nil
        elapsedTime = 0
        return (start, end)
    }

    func formattedElapsed() -> String {
        TimeTracker.formatDuration(elapsedTime)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
