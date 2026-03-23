import Foundation

enum ReportGenerator {
    /// Minimal CSV: header row, one row per task (`start`/`end` are local time-of-day only; `duration_minutes` is decimal), then a `Total` row with summed minutes.
    static func makeCSVData(tasks: [TaskEntry], calendar: Calendar = .current) -> Data? {
        let tf = DateFormatter()
        tf.dateStyle = .none
        tf.timeStyle = .short
        tf.calendar = calendar
        tf.timeZone = calendar.timeZone

        var lines: [String] = []
        lines.append("description,start,end,duration_minutes")
        var totalSeconds: TimeInterval = 0
        for task in tasks {
            totalSeconds += task.duration
            let minutes = task.duration / 60.0
            let row = [
                csvField(task.description),
                csvField(tf.string(from: task.startTime)),
                csvField(tf.string(from: task.endTime)),
                csvField(String(format: "%.2f", minutes))
            ].joined(separator: ",")
            lines.append(row)
        }
        let totalMinutes = totalSeconds / 60.0
        let totalRow = [
            csvField("Total"),
            "",
            "",
            String(format: "%.2f", totalMinutes)
        ].joined(separator: ",")
        lines.append(totalRow)
        return lines.joined(separator: "\n").data(using: .utf8)
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh %02dm %02ds", h, m, s)
        }
        if m > 0 {
            return String(format: "%dm %02ds", m, s)
        }
        return String(format: "%ds", s)
    }
}
