import XCTest
@testable import CafePulse

final class LocalStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any existing test data
        let appSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CafePulse", isDirectory: true)
        try? FileManager.default.removeItem(at: appSupportURL)
    }

    override func tearDown() {
        // Clean up after tests
        let appSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CafePulse", isDirectory: true)
        try? FileManager.default.removeItem(at: appSupportURL)
        super.tearDown()
    }

    func testLoadFromEmptyDirectoryReturnsDefault() async throws {
        let store = LocalStore(fileManager: .default)
        let snapshot = try await store.loadSnapshot()
        XCTAssertTrue(snapshot.sessions.isEmpty)
        XCTAssertTrue(snapshot.audioSamples.isEmpty)
        XCTAssertTrue(snapshot.crowdEstimates.isEmpty)
    }

    func testPersistAndLoadRoundTrip() async throws {
        let store = LocalStore(fileManager: .default)

        let session = Session(cafeName: "Test Cafe", location: "Berlin")
        let sample = AudioSample(
            sessionId: session.id,
            overallDB: -30,
            musicBandDB: -40,
            voiceBandDB: -35,
            peakDB: -20,
            spectralFlatness: 0.3,
            selfTalkDetected: false,
            voiceBandVariance: -50
        )
        let estimate = CrowdEstimate(sessionId: session.id, fullness: .half, peopleCount: 10)

        let snapshot = AppSnapshot(
            sessions: [session],
            audioSamples: [sample],
            crowdEstimates: [estimate]
        )

        try await store.persist(snapshot)
        let loaded = try await store.loadSnapshot()

        XCTAssertEqual(loaded.sessions.count, 1)
        XCTAssertEqual(loaded.sessions.first?.cafeName, "Test Cafe")
        XCTAssertEqual(loaded.audioSamples.count, 1)
        XCTAssertEqual(loaded.audioSamples.first?.overallDB ?? 0, -30, accuracy: 0.01)
        XCTAssertEqual(loaded.crowdEstimates.count, 1)
        XCTAssertEqual(loaded.crowdEstimates.first?.fullness, .half)
    }
}
