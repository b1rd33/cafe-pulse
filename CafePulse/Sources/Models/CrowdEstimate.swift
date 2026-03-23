import Foundation

enum CrowdFullness: String, CaseIterable, Codable, Identifiable, Sendable {
    case empty
    case quarter
    case half
    case threeQuarters = "three_quarters"
    case full

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .empty:
            "Empty"
        case .quarter:
            "Quarter"
        case .half:
            "Half"
        case .threeQuarters:
            "Three Quarters"
        case .full:
            "Full"
        }
    }
}

struct CrowdEstimate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    var fullness: CrowdFullness
    var peopleCount: Int?
    var syncedAt: Date?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        timestamp: Date = .now,
        fullness: CrowdFullness,
        peopleCount: Int? = nil,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.fullness = fullness
        self.peopleCount = peopleCount
        self.syncedAt = syncedAt
    }
}
