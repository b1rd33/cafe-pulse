import Foundation

struct Session: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var cafeName: String
    var location: String?
    var startedAt: Date
    var endedAt: Date?
    var tags: [String]
    var syncedAt: Date?

    init(
        id: UUID = UUID(),
        cafeName: String,
        location: String? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        tags: [String] = [],
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.cafeName = cafeName
        self.location = location
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tags = tags
        self.syncedAt = syncedAt
    }

    var isActive: Bool {
        endedAt == nil
    }
}
