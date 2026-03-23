import Foundation

struct AppSnapshot: Codable, Sendable {
    var sessions: [Session] = []
    var audioSamples: [AudioSample] = []
    var crowdEstimates: [CrowdEstimate] = []
    var settings: AppSettings = .default
}
