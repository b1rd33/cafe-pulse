import Foundation

struct AudioSample: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let overallDB: Float
    let musicBandDB: Float
    let voiceBandDB: Float
    let peakDB: Float

    /// Spectral flatness of voice band (0=quiet/tonal, 1=noise-like/crowd babble).
    /// Automatic crowd density proxy — validates manual crowd estimates.
    let spectralFlatness: Float

    /// True if the user was likely talking during this sample.
    /// Based on voice energy being >12dB above running average (proximity effect).
    let selfTalkDetected: Bool

    /// Temporal variance of voice energy across FFT windows.
    /// Higher = more crowd activity (overlapping conversations).
    let voiceBandVariance: Float

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
        voiceBandVariance: Float = -120
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
    }
}
