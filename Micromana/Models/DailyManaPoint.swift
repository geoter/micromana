import Foundation

/// One calendar day’s tracked time vs mana budget (for charts).
struct DailyManaPoint: Identifiable {
    let id: Date
    /// Start of calendar day.
    let day: Date
    let shortLabel: String
    let consumed: TimeInterval
    let budget: TimeInterval

    var consumedHours: Double { consumed / 3600 }
    var budgetHours: Double { budget / 3600 }
}
