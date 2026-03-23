import AVFoundation
import Foundation

enum MicrophonePermissionState: Sendable {
    case undetermined
    case denied
    case granted
}

struct AudioMeasurement: Sendable {
    let timestamp: Date
    let overallDB: Float
    let musicBandDB: Float
    let voiceBandDB: Float
    let peakDB: Float

    /// Spectral flatness of the voice band (0=tonal/quiet, 1=noise-like/crowd babble).
    /// Higher values suggest more overlapping speakers — automatic crowd density proxy.
    let spectralFlatness: Float

    /// True if a near-field voice was detected (user likely talking).
    /// These samples should be flagged in analysis — the user's voice
    /// is ~16-400x louder than crowd due to proximity.
    let selfTalkDetected: Bool

    /// Temporal variance of voice-band energy across FFT windows.
    /// Higher variance = more crowd activity (conversations starting/stopping).
    let voiceBandVariance: Float
}

enum AudioCaptureEngineError: LocalizedError {
    case microphonePermissionDenied
    case missingInputDevice
    case unsupportedBufferFormat

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access is required before CafePulse can start sampling."
        case .missingInputDevice:
            "No microphone input device is currently available."
        case .unsupportedBufferFormat:
            "CafePulse could not read microphone buffers in Float32 format."
        }
    }
}

final class AudioCaptureEngine {
    var onMeasurement: ((AudioMeasurement) -> Void)?
    var onError: ((Error) -> Void)?

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "CafePulse.AudioCaptureEngine.analysis")
    private let analyzer: FFTBandAnalyzer
    private let fftSize: Int
    private let hopSize: Int

    private var accumulator: MetricsAccumulator?
    private var sampleInterval: TimeInterval
    private(set) var isRunning = false

    init(sampleInterval: TimeInterval = AppSettings.default.sampleIntervalSeconds, fftSize: Int = 4_096) {
        self.sampleInterval = sampleInterval
        self.fftSize = fftSize
        self.hopSize = max(fftSize / 2, 1)
        do {
            analyzer = try FFTBandAnalyzer(fftSize: fftSize)
        } catch {
            fatalError("Failed to initialize FFT analyzer: \(error.localizedDescription)")
        }
    }

    static func currentPermissionState() -> MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .granted
        case .notDetermined:
            .undetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func requestPermission() async -> Bool {
        let currentState = Self.currentPermissionState()
        switch currentState {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func updateSampleInterval(_ value: TimeInterval) {
        sampleInterval = value
        analysisQueue.async { [weak self] in
            self?.accumulator?.updateSampleInterval(value)
        }
    }

    func start() throws {
        guard Self.currentPermissionState() == .granted else {
            throw AudioCaptureEngineError.microphonePermissionDenied
        }

        guard !isRunning else {
            return
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureEngineError.missingInputDevice
        }

        let bufferSize = AVAudioFrameCount(fftSize)
        accumulator = MetricsAccumulator(
            sampleRate: inputFormat.sampleRate,
            sampleInterval: sampleInterval,
            fftSize: fftSize,
            hopSize: hopSize
        )

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.analysisQueue.async {
                self?.process(buffer: buffer, sampleRate: inputFormat.sampleRate)
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        analysisQueue.async { [weak self] in
            self?.accumulator = nil
        }

        isRunning = false
    }

    private func process(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let monoSamples = extractMonoSamples(from: buffer) else {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(AudioCaptureEngineError.unsupportedBufferFormat)
            }
            return
        }

        guard let accumulator else {
            return
        }

        if let measurement = accumulator.append(samples: monoSamples, analyzer: analyzer, timestamp: .now) {
            DispatchQueue.main.async { [weak self] in
                self?.onMeasurement?(measurement)
            }
        }
    }

    private func extractMonoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0 else {
            return []
        }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        var monoSamples = [Float](repeating: 0, count: frameCount)
        for channelIndex in 0..<channelCount {
            let channelSamples = UnsafeBufferPointer(start: channelData[channelIndex], count: frameCount)
            for frameIndex in 0..<frameCount {
                monoSamples[frameIndex] += channelSamples[frameIndex]
            }
        }

        let scale = 1 / Float(channelCount)
        for frameIndex in 0..<frameCount {
            monoSamples[frameIndex] *= scale
        }

        return monoSamples
    }
}

// MARK: - MetricsAccumulator

private final class MetricsAccumulator {
    private let sampleRate: Double
    private let fftSize: Int
    private let hopSize: Int

    private var sampleInterval: TimeInterval
    private var pendingSamples: [Float] = []
    private var totalSquareSum: Double = 0
    private var totalFrameCount = 0
    private var peakAmplitude: Float = 0
    private var bandPower = FFTBandPower()
    private var analyzedWindowCount = 0

    // Enhanced metrics accumulators
    private var spectralFlatnessSum: Double = 0
    private var voicePowerPerWindow: [Double] = []

    // Self-talk detection: track short-term voice energy spikes
    private var voiceEnergyRunningAvg: Double = -80
    private static let selfTalkThresholdDB: Double = 12 // dB above running average

    init(sampleRate: Double, sampleInterval: TimeInterval, fftSize: Int, hopSize: Int) {
        self.sampleRate = sampleRate
        self.sampleInterval = sampleInterval
        self.fftSize = fftSize
        self.hopSize = hopSize
    }

    func updateSampleInterval(_ value: TimeInterval) {
        sampleInterval = value
    }

    func append(samples: [Float], analyzer: FFTBandAnalyzer, timestamp: Date) -> AudioMeasurement? {
        guard !samples.isEmpty else {
            return nil
        }

        for sample in samples {
            let absSample = abs(sample)
            peakAmplitude = max(peakAmplitude, absSample)
            totalSquareSum += Double(sample * sample)
        }

        totalFrameCount += samples.count
        pendingSamples.append(contentsOf: samples)

        while pendingSamples.count >= fftSize {
            let power = analyzer.analyze(samples: pendingSamples.prefix(fftSize), sampleRate: sampleRate)
            bandPower.add(power)
            spectralFlatnessSum += power.voiceBandSpectralFlatness
            voicePowerPerWindow.append(power.voiceProxyPower)
            analyzedWindowCount += 1
            pendingSamples.removeFirst(hopSize)
        }

        let elapsedSeconds = Double(totalFrameCount) / sampleRate
        guard elapsedSeconds >= sampleInterval else {
            return nil
        }

        let measurement = makeMeasurement(timestamp: timestamp)
        reset()
        return measurement
    }

    private func makeMeasurement(timestamp: Date) -> AudioMeasurement {
        let frameCount = max(totalFrameCount, 1)
        let rms = sqrt(totalSquareSum / Double(frameCount))
        let windowCount = max(analyzedWindowCount, 1)
        let averagedBandPower = analyzedWindowCount > 0
            ? bandPower.scaled(by: 1 / Double(analyzedWindowCount))
            : bandPower

        // Spectral flatness: average across all windows
        let avgSpectralFlatness = spectralFlatnessSum / Double(windowCount)

        // Voice band variance: how much voice energy fluctuates across windows.
        // High variance = conversations starting/stopping = crowd activity.
        let voiceVariance = computeVariance(voicePowerPerWindow)

        // Self-talk detection: is the current voice energy way above the running average?
        let currentVoiceDB = Self.dbFromPower(averagedBandPower.voiceProxyPower)
        let selfTalkDetected = Double(currentVoiceDB) - voiceEnergyRunningAvg > Self.selfTalkThresholdDB

        // Update running average with exponential smoothing (slow adaptation)
        let alpha = 0.1
        voiceEnergyRunningAvg = alpha * Double(currentVoiceDB) + (1 - alpha) * voiceEnergyRunningAvg

        return AudioMeasurement(
            timestamp: timestamp,
            overallDB: Self.dbFromAmplitude(rms),
            musicBandDB: Self.dbFromPower(averagedBandPower.musicProxyPower),
            voiceBandDB: Self.dbFromPower(averagedBandPower.voiceProxyPower),
            peakDB: Self.dbFromAmplitude(Double(peakAmplitude)),
            spectralFlatness: Float(avgSpectralFlatness),
            selfTalkDetected: selfTalkDetected,
            voiceBandVariance: Self.dbFromPower(voiceVariance)
        )
    }

    private func computeVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSquaredDiff = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sumSquaredDiff / Double(values.count - 1)
    }

    private func reset() {
        pendingSamples.removeAll(keepingCapacity: true)
        totalSquareSum = 0
        totalFrameCount = 0
        peakAmplitude = 0
        bandPower = FFTBandPower()
        analyzedWindowCount = 0
        spectralFlatnessSum = 0
        voicePowerPerWindow.removeAll(keepingCapacity: true)
    }

    private static func dbFromAmplitude(_ amplitude: Double) -> Float {
        let clamped = max(amplitude, 0.000_000_1)
        return max(Float(20 * log10(clamped)), -120)
    }

    private static func dbFromPower(_ power: Double) -> Float {
        let clamped = max(power, 0.000_000_1)
        return max(Float(10 * log10(clamped)), -120)
    }
}
