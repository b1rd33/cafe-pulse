import XCTest
@testable import CafePulse

final class CSVExporterTests: XCTestCase {
    let exporter = CSVExporter()
    let tempDir = FileManager.default.temporaryDirectory

    // Test 1: Empty snapshot → header only
    func testEmptySnapshotProducesHeaderOnly() throws {
        let url = tempDir.appendingPathComponent("test_empty.csv")
        try exporter.export(snapshot: AppSnapshot(), to: url)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("session_id,cafe_name,timestamp,"))
        // Should have header but no data rows
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, "Empty snapshot should only have header")
        try? FileManager.default.removeItem(at: url)
    }

    // Test 2: Header contains new columns
    func testHeaderContainsAllColumns() throws {
        let url = tempDir.appendingPathComponent("test_header.csv")
        try exporter.export(snapshot: AppSnapshot(), to: url)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("spectral_flatness"))
        XCTAssertTrue(content.contains("self_talk_detected"))
        XCTAssertTrue(content.contains("voice_band_variance"))
        XCTAssertTrue(content.contains("crowd_fullness"))
        XCTAssertTrue(content.contains("people_count"))
        try? FileManager.default.removeItem(at: url)
    }

    // Test 3: One sample produces one data row
    func testOneSampleProducesOneRow() throws {
        let sessionId = UUID()
        let now = Date()
        let snapshot = AppSnapshot(
            sessions: [Session(id: sessionId, cafeName: "TestCafe", startedAt: now)],
            audioSamples: [AudioSample(sessionId: sessionId, timestamp: now, overallDB: -30, musicBandDB: -40, voiceBandDB: -35, peakDB: -20)],
            crowdEstimates: []
        )
        let url = tempDir.appendingPathComponent("test_one.csv")
        try exporter.export(snapshot: snapshot, to: url)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "Should have header + 1 data row")
        XCTAssertTrue(lines[1].contains("TestCafe"))
        XCTAssertTrue(lines[1].contains("-30.00"))
        try? FileManager.default.removeItem(at: url)
    }

    // Test 4: CSV escaping — cafe name with comma
    func testCafeNameWithCommaIsQuoted() throws {
        let sessionId = UUID()
        let now = Date()
        let snapshot = AppSnapshot(
            sessions: [Session(id: sessionId, cafeName: "Coffee, Tea & Me", startedAt: now)],
            audioSamples: [AudioSample(sessionId: sessionId, timestamp: now, overallDB: -30, musicBandDB: -40, voiceBandDB: -35, peakDB: -20)],
            crowdEstimates: []
        )
        let url = tempDir.appendingPathComponent("test_escape.csv")
        try exporter.export(snapshot: snapshot, to: url)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("\"Coffee, Tea & Me\""), "Cafe name with comma should be quoted")
        try? FileManager.default.removeItem(at: url)
    }
}
