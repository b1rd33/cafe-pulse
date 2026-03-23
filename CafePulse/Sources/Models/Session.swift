import Foundation

struct Session: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var cafeName: String
    var location: String?
    var startedAt: Date
    var endedAt: Date?
    var tags: [String]
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case cafeName = "cafe_name"
        case location
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case tags
        case syncedAt = "synced_at"
    }

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
