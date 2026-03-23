import Foundation

struct AudioSample: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let overallDB: Float
    let musicBandDB: Float
    let voiceBandDB: Float
    let peakDB: Float

    // Explicit CodingKeys because Swift's convertToSnakeCase
    // splits "overallDB" → "overall_d_b" instead of "overall_db"
    enum CodingKeys: String, CodingKey {
        case id, sessionId = "session_id", timestamp
        case overallDB = "overall_db"
        case musicBandDB = "music_band_db"
        case voiceBandDB = "voice_band_db"
        case peakDB = "peak_db"
        case spectralFlatness = "spectral_flatness"
        case selfTalkDetected = "self_talk_detected"
        case voiceBandVariance = "voice_band_variance"
        case syncedAt = "synced_at"
    }

    /// Spectral flatness of voice band (0=quiet/tonal, 1=noise-like/crowd babble).
    /// Automatic crowd density proxy — validates manual crowd estimates.
    let spectralFlatness: Float

    /// True if the user was likely talking during this sample.
    /// Based on voice energy being >12dB above running average (proximity effect).
    let selfTalkDetected: Bool

    /// Temporal variance of voice energy across FFT windows.
    /// Higher = more crowd activity (overlapping conversations).
    let voiceBandVariance: Float
    var syncedAt: Date?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        timestamp: Date = .now,
        overallDB: Float,
        musicBandDB: Float,
        voiceBandDB: Float,
        peakDB: Float,
        spectralFlatness: Float = 0,
        selfTalkDetected: Bool = false,
        voiceBandVariance: Float = -120,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.overallDB = overallDB
        self.musicBandDB = musicBandDB
        self.voiceBandDB = voiceBandDB
        self.peakDB = peakDB
        self.spectralFlatness = spectralFlatness
        self.selfTalkDetected = selfTalkDetected
        self.voiceBandVariance = voiceBandVariance
        self.syncedAt = syncedAt
    }
}
