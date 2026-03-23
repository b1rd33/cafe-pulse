import XCTest
@testable import CafePulse

final class ModelsTests: XCTestCase {
    // Use same strategy as LocalStore — but AudioSample has explicit CodingKeys
    // so snake_case strategy is fine (it won't double-transform explicit keys)
    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Session

    func testSessionCodableRoundTrip() throws {
        let session = Session(cafeName: "Blue Bottle", location: "Berlin", tags: ["morning", "busy"])
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(Session.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.cafeName, session.cafeName)
        XCTAssertEqual(decoded.location, session.location)
        XCTAssertEqual(decoded.tags, session.tags)
        XCTAssertNil(decoded.syncedAt)
    }

    func testSessionIsActive() {
        let active = Session(cafeName: "Test")
        XCTAssertTrue(active.isActive)

        var ended = Session(cafeName: "Test")
        ended.endedAt = .now
        XCTAssertFalse(ended.isActive)
    }

    func testSessionSyncedAtDefaultsToNil() {
        let session = Session(cafeName: "Test")
        XCTAssertNil(session.syncedAt)
    }

    // MARK: - AudioSample

    func testAudioSampleCodableRoundTrip() throws {
        let sample = AudioSample(
            sessionId: UUID(),
            overallDB: -30.5,
            musicBandDB: -45.2,
            voiceBandDB: -38.1,
            peakDB: -15.0,
            spectralFlatness: 0.42,
            selfTalkDetected: true,
            voiceBandVariance: -55.3
        )
        let data = try encoder.encode(sample)
        let decoded = try decoder.decode(AudioSample.self, from: data)
        XCTAssertEqual(decoded.id, sample.id)
        XCTAssertEqual(decoded.overallDB, sample.overallDB, accuracy: 0.01)
        XCTAssertEqual(decoded.spectralFlatness, sample.spectralFlatness, accuracy: 0.01)
        XCTAssertTrue(decoded.selfTalkDetected)
        XCTAssertEqual(decoded.voiceBandVariance, sample.voiceBandVariance, accuracy: 0.01)
        XCTAssertNil(decoded.syncedAt)
    }

    // MARK: - CrowdEstimate

    func testCrowdEstimateCodableRoundTrip() throws {
        let estimate = CrowdEstimate(sessionId: UUID(), fullness: .threeQuarters, peopleCount: 25)
        let data = try encoder.encode(estimate)
        let decoded = try decoder.decode(CrowdEstimate.self, from: data)
        XCTAssertEqual(decoded.fullness, .threeQuarters)
        XCTAssertEqual(decoded.peopleCount, 25)
        XCTAssertNil(decoded.syncedAt)
    }

    func testCrowdFullnessRawValuesMatchDBConstraint() {
        // DB CHECK: ('empty','quarter','half','three_quarters','full')
        XCTAssertEqual(CrowdFullness.empty.rawValue, "empty")
        XCTAssertEqual(CrowdFullness.quarter.rawValue, "quarter")
        XCTAssertEqual(CrowdFullness.half.rawValue, "half")
        XCTAssertEqual(CrowdFullness.threeQuarters.rawValue, "three_quarters")
        XCTAssertEqual(CrowdFullness.full.rawValue, "full")
    }
}
