import Foundation

struct AppSettings: Codable, Equatable {
    var elevenLabsAPIKey: String
    /// Total available minutes per day (“mana” budget).
    var dailyManaMinutes: Int
    /// Security-scoped bookmark for a folder containing `tasks.json` (session log). `nil` uses the default Application Support folder.
    var logDirectoryBookmarkData: Data?

    static let `default` = AppSettings(elevenLabsAPIKey: "", dailyManaMinutes: 8 * 60, logDirectoryBookmarkData: nil)
}
