import Foundation

struct Session: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var cafeName: String
    var location: String?
    var startedAt: Date
    var endedAt: Date?
    var tags: [String]

    init(
        id: UUID = UUID(),
        cafeName: String,
        location: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.cafeName = cafeName
        self.location = location
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tags = tags
    }

    var isActive: Bool {
        endedAt == nil
    }
}
