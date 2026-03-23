import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var sampleIntervalSeconds: Double = 5
    var crowdPromptIntervalSeconds: Double = 15 * 60

    enum CodingKeys: String, CodingKey {
        case sampleIntervalSeconds = "sample_interval_seconds"
        case crowdPromptIntervalSeconds = "crowd_prompt_interval_seconds"
    }

    static let `default` = AppSettings()
}

struct StartSessionDraft: Equatable, Sendable {
    var cafeName: String = ""
    var location: String = ""
    var tagsText: String = ""

    var normalizedCafeName: String {
        cafeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLocation: String? {
        let value = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct CrowdEstimateDraft: Equatable, Sendable {
    var fullness: CrowdFullness = .half
    var includePeopleCount = false
    var peopleCount = 12

    var resolvedPeopleCount: Int? {
        includePeopleCount ? max(0, peopleCount) : nil
    }
}
