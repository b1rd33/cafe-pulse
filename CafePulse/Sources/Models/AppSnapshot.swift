import Foundation

struct AppSnapshot: Codable, Sendable {
    var sessions: [Session] = []
    var audioSamples: [AudioSample] = []
    var crowdEstimates: [CrowdEstimate] = []
    var settings: AppSettings = .default

    enum CodingKeys: String, CodingKey {
        case sessions
        case audioSamples = "audio_samples"
        case crowdEstimates = "crowd_estimates"
        case settings
    }
}
