import Foundation

enum SyncState: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
    case offline
}

@MainActor
final class SyncManager: ObservableObject {
    @Published var syncState: SyncState = .idle

    private let client: SupabaseClient
    private weak var appModel: AppModel?
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 120  // 2 minutes

    init(client: SupabaseClient, appModel: AppModel) {
        self.client = client
        self.appModel = appModel
    }

    /// Start periodic 2-minute sync timer. Call when session starts.
    func startPeriodicSync() {
        stopPeriodicSync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncNow()
            }
        }
        // Do an immediate sync too
        Task { await syncNow() }
    }

    /// Stop the periodic timer. Call when session ends (after calling syncNow for final flush).
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Immediate sync of all unsynced records.
    func syncNow() async {
        guard let appModel else { return }
        guard client.isAuthenticated else {
            syncState = .offline
            return
        }

        syncState = .syncing

        do {
            // Refresh token before sync
            try await client.refreshTokenIfNeeded()

            // 1. Upsert unsynced sessions (must go first — audio_samples reference session_id)
            let unsyncedSessions = appModel.unsyncedSessions
            for session in unsyncedSessions {
                try await client.upsertSession(session)
                appModel.markSessionSynced(id: session.id)
            }

            // 2. Re-upsert sessions where endedAt changed after initial sync
            let updatedSessions = appModel.sessionsNeedingUpdate
            for session in updatedSessions {
                try await client.upsertSession(session)
                appModel.markSessionSynced(id: session.id)
            }

            // 3. Batch upsert unsynced audio samples (max 100 per request)
            let unsyncedSamples = appModel.unsyncedAudioSamples
            let sampleBatches = stride(from: 0, to: unsyncedSamples.count, by: 100).map {
                Array(unsyncedSamples[$0..<min($0 + 100, unsyncedSamples.count)])
            }
            for batch in sampleBatches {
                try await client.upsertAudioSamples(batch)
                appModel.markAudioSamplesSynced(ids: Set(batch.map(\.id)))
            }

            // 4. Batch upsert unsynced crowd estimates
            let unsyncedEstimates = appModel.unsyncedCrowdEstimates
            if !unsyncedEstimates.isEmpty {
                try await client.upsertCrowdEstimates(unsyncedEstimates)
                appModel.markCrowdEstimatesSynced(ids: Set(unsyncedEstimates.map(\.id)))
            }

            syncState = appModel.hasUnsyncedRecords ? .syncing : .synced

        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    /// Run on app launch: sync all unsynced records, then stop.
    func drainUnsyncedQueue() async {
        guard let appModel, appModel.hasUnsyncedRecords else { return }
        await syncNow()
        // If still unsynced (error), start periodic retry
        if appModel.hasUnsyncedRecords {
            startPeriodicSync()
        }
    }
}
