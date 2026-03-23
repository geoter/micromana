import Foundation

struct TaskEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let description: String

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    init(id: UUID = UUID(), startTime: Date, endTime: Date, description: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.description = description
    }
}
