import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var audioSamples: [AudioSample] = []
    @Published private(set) var crowdEstimates: [CrowdEstimate] = []
    @Published var settings: AppSettings = .default
    @Published var currentSession: Session?
    @Published var microphonePermission: MicrophonePermissionState
    @Published var isStartSessionFormVisible = false
    @Published var startSessionDraft = StartSessionDraft()
    @Published var crowdEstimateDraft = CrowdEstimateDraft()
    @Published var pendingCrowdPrompt = false
    @Published var statusMessage: String?
    @Published var lastAudioSample: AudioSample?
    @Published private(set) var isSampling = false
    @Published var isMainWindowVisible = false

    var presentCrowdPrompt: (() -> Void)?
    var dismissCrowdPrompt: (() -> Void)?

    private let store = LocalStore()
    private let exporter = CSVExporter()
    private let audioEngine: AudioCaptureEngine
    private var crowdPromptTimer: Timer?

    init() {
        microphonePermission = AudioCaptureEngine.currentPermissionState()
        audioEngine = AudioCaptureEngine(sampleInterval: AppSettings.default.sampleIntervalSeconds)

        audioEngine.onMeasurement = { [weak self] measurement in
            Task { @MainActor in
                self?.handleMeasurement(measurement)
            }
        }

        audioEngine.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleAudioError(error)
            }
        }

        Task {
            await loadSnapshot()
        }
    }

    deinit {
        crowdPromptTimer?.invalidate()
        audioEngine.stop()
    }

    // MARK: - Sync Queries

    var unsyncedSessions: [Session] {
        sessions.filter { $0.syncedAt == nil }
    }

    var sessionsNeedingUpdate: [Session] {
        sessions.filter { $0.syncedAt != nil && $0.endedAt != nil && $0.syncedAt! < $0.endedAt! }
    }

    var unsyncedAudioSamples: [AudioSample] {
        audioSamples.filter { $0.syncedAt == nil }
    }

    var unsyncedCrowdEstimates: [CrowdEstimate] {
        crowdEstimates.filter { $0.syncedAt == nil }
    }

    var hasUnsyncedRecords: Bool {
        !unsyncedSessions.isEmpty || !unsyncedAudioSamples.isEmpty
            || !unsyncedCrowdEstimates.isEmpty || !sessionsNeedingUpdate.isEmpty
    }

    func markSessionSynced(id: UUID) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].syncedAt = .now
        }
        persistCurrentState()
    }

    func markAudioSamplesSynced(ids: Set<UUID>) {
        for i in audioSamples.indices where ids.contains(audioSamples[i].id) {
            audioSamples[i].syncedAt = .now
        }
        persistCurrentState()
    }

    func markCrowdEstimatesSynced(ids: Set<UUID>) {
        for i in crowdEstimates.indices where ids.contains(crowdEstimates[i].id) {
            crowdEstimates[i].syncedAt = .now
        }
        persistCurrentState()
    }

    // MARK: - Cafe Suggestions

    var previousCafeSuggestions: [String] {
        Array(Set(sessions.map(\.cafeName)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var currentSessionSampleCount: Int {
        guard let currentSession else {
            return 0
        }

        return audioSamples.lazy.filter { $0.sessionId == currentSession.id }.count
    }

    var currentSessionCrowdCount: Int {
        guard let currentSession else {
            return 0
        }

        return crowdEstimates.lazy.filter { $0.sessionId == currentSession.id }.count
    }

    var currentSessionDurationText: String {
        guard let currentSession else {
            return "Not running"
        }

        let endDate = currentSession.endedAt ?? .now
        return Self.durationFormatter.string(from: currentSession.startedAt, to: endDate) ?? "Just started"
    }

    func showStartSessionForm() {
        isStartSessionFormVisible = true
        statusMessage = nil
    }

    func cancelStartSession() {
        isStartSessionFormVisible = false
        startSessionDraft = StartSessionDraft()
    }

    func startSession() {
        let draft = startSessionDraft
        Task {
            await startSession(using: draft)
        }
    }

    func endSession() {
        guard let activeSession = currentSession else {
            return
        }

        audioEngine.stop()
        isSampling = false
        crowdPromptTimer?.invalidate()
        pendingCrowdPrompt = false
        dismissCrowdPrompt?()

        if let index = sessions.firstIndex(where: { $0.id == activeSession.id }) {
            sessions[index].endedAt = .now
        }

        currentSession = nil
        statusMessage = "Session ended."
        persistCurrentState()
    }

    func presentCrowdEstimatePrompt() {
        guard currentSession != nil else {
            return
        }

        pendingCrowdPrompt = true
        crowdEstimateDraft = CrowdEstimateDraft()
        presentCrowdPrompt?()
    }

    func dismissCrowdEstimatePrompt() {
        pendingCrowdPrompt = false
        crowdEstimateDraft = CrowdEstimateDraft()
        dismissCrowdPrompt?()
    }

    func submitCrowdEstimate() {
        guard let currentSession else {
            return
        }

        let estimate = CrowdEstimate(
            sessionId: currentSession.id,
            fullness: crowdEstimateDraft.fullness,
            peopleCount: crowdEstimateDraft.resolvedPeopleCount
        )

        crowdEstimates.append(estimate)
        pendingCrowdPrompt = false
        crowdEstimateDraft = CrowdEstimateDraft()
        statusMessage = "Crowd estimate logged."
        dismissCrowdPrompt?()
        persistCurrentState()
    }

    func updateSampleInterval(_ seconds: Double) {
        settings.sampleIntervalSeconds = seconds
        audioEngine.updateSampleInterval(seconds)
        statusMessage = "Sample interval set to \(Int(seconds))s."
        persistCurrentState()
    }

    func updateCrowdPromptInterval(minutes: Double) {
        settings.crowdPromptIntervalSeconds = minutes * 60
        scheduleCrowdPromptTimer()
        statusMessage = "Crowd prompt interval set to \(Int(minutes)) minutes."
        persistCurrentState()
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFileName

        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.commaSeparatedText]
        } else {
            panel.allowedFileTypes = ["csv"]
        }

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            try exporter.export(snapshot: snapshot, to: destinationURL)
            statusMessage = "Exported CSV to \(destinationURL.lastPathComponent)."
        } catch {
            statusMessage = "CSV export failed: \(error.localizedDescription)"
        }
    }

    private func loadSnapshot() async {
        do {
            let loadedSnapshot = try await store.loadSnapshot()
            sessions = loadedSnapshot.sessions.sorted { $0.startedAt < $1.startedAt }
            audioSamples = loadedSnapshot.audioSamples.sorted { $0.timestamp < $1.timestamp }
            crowdEstimates = loadedSnapshot.crowdEstimates.sorted { $0.timestamp < $1.timestamp }
            settings = loadedSnapshot.settings

            audioEngine.updateSampleInterval(settings.sampleIntervalSeconds)
            lastAudioSample = audioSamples.last
            currentSession = sessions.first(where: \.isActive)

            if currentSession != nil {
                scheduleCrowdPromptTimer()
                await resumeSamplingIfPossible()
            }
        } catch {
            statusMessage = "Failed to load local data: \(error.localizedDescription)"
        }
    }

    private func resumeSamplingIfPossible() async {
        microphonePermission = AudioCaptureEngine.currentPermissionState()
        guard currentSession != nil else {
            return
        }

        guard microphonePermission == .granted else {
            statusMessage = "An active session was restored, but microphone access still needs approval."
            return
        }

        do {
            try audioEngine.start()
            isSampling = true
        } catch {
            statusMessage = "Failed to resume microphone sampling: \(error.localizedDescription)"
        }
    }

    private func startSession(using draft: StartSessionDraft) async {
        guard currentSession == nil else {
            statusMessage = "End the current session before starting a new one."
            return
        }

        guard !draft.normalizedCafeName.isEmpty else {
            statusMessage = "Enter a cafe name to start a session."
            return
        }

        let granted = await ensureMicrophonePermission()
        guard granted else {
            statusMessage = "Microphone access is required before CafePulse can start sampling."
            return
        }

        do {
            audioEngine.updateSampleInterval(settings.sampleIntervalSeconds)
            try audioEngine.start()

            let session = Session(
                cafeName: draft.normalizedCafeName,
                location: draft.normalizedLocation,
                tags: draft.parsedTags
            )

            currentSession = session
            sessions.append(session)
            isSampling = true
            pendingCrowdPrompt = false
            isStartSessionFormVisible = false
            startSessionDraft = StartSessionDraft()
            statusMessage = "Session started."

            scheduleCrowdPromptTimer()
            persistCurrentState()
        } catch {
            isSampling = false
            statusMessage = "Failed to start microphone sampling: \(error.localizedDescription)"
        }
    }

    private func ensureMicrophonePermission() async -> Bool {
        microphonePermission = AudioCaptureEngine.currentPermissionState()
        guard microphonePermission != .granted else {
            return true
        }

        let granted = await audioEngine.requestPermission()
        microphonePermission = AudioCaptureEngine.currentPermissionState()
        return granted
    }

    private func handleMeasurement(_ measurement: AudioMeasurement) {
        guard let currentSession else {
            return
        }

        let sample = AudioSample(
            sessionId: currentSession.id,
            timestamp: measurement.timestamp,
            overallDB: measurement.overallDB,
            musicBandDB: measurement.musicBandDB,
            voiceBandDB: measurement.voiceBandDB,
            peakDB: measurement.peakDB,
            spectralFlatness: measurement.spectralFlatness,
            selfTalkDetected: measurement.selfTalkDetected,
            voiceBandVariance: measurement.voiceBandVariance
        )

        audioSamples.append(sample)
        lastAudioSample = sample
        persistCurrentState()
    }

    private func handleAudioError(_ error: Error) {
        isSampling = false
        statusMessage = error.localizedDescription
    }

    private func scheduleCrowdPromptTimer() {
        crowdPromptTimer?.invalidate()

        guard currentSession != nil else {
            return
        }

        crowdPromptTimer = Timer.scheduledTimer(withTimeInterval: settings.crowdPromptIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.presentCrowdEstimatePrompt()
            }
        }
    }

    private func persistCurrentState() {
        let snapshot = snapshot
        Task {
            do {
                try await store.persist(snapshot)
            } catch {
                await MainActor.run {
                    self.statusMessage = "Failed to save local data: \(error.localizedDescription)"
                }
            }
        }
    }

    private var snapshot: AppSnapshot {
        AppSnapshot(
            sessions: sessions,
            audioSamples: audioSamples,
            crowdEstimates: crowdEstimates,
            settings: settings
        )
    }

    private var defaultExportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "cafepulse-\(formatter.string(from: .now)).csv"
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}
