import XCTest
@testable import CafePulse

final class KeychainHelperTests: XCTestCase {
    // Use unique test keys to avoid collision with the running app
    let testKey = "com.cafepulse.test.\(UUID().uuidString)"

    override func tearDown() {
        KeychainHelper.delete(key: testKey)
        super.tearDown()
    }

    func testSaveAndLoadString() {
        let saved = KeychainHelper.save(key: testKey, string: "test-token-123")
        XCTAssertTrue(saved)

        let loaded = KeychainHelper.loadString(key: testKey)
        XCTAssertEqual(loaded, "test-token-123")
    }

    func testLoadNonexistentKeyReturnsNil() {
        let loaded = KeychainHelper.loadString(key: "com.cafepulse.test.nonexistent")
        XCTAssertNil(loaded)
    }

    func testDeleteRemovesValue() {
        _ = KeychainHelper.save(key: testKey, string: "to-delete")
        KeychainHelper.delete(key: testKey)
        XCTAssertNil(KeychainHelper.loadString(key: testKey))
    }

    func testSaveOverwritesPreviousValue() {
        _ = KeychainHelper.save(key: testKey, string: "first")
        _ = KeychainHelper.save(key: testKey, string: "second")
        XCTAssertEqual(KeychainHelper.loadString(key: testKey), "second")
    }

    func testSaveAndLoadDate() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let saved = KeychainHelper.saveDate(key: testKey, date: date)
        XCTAssertTrue(saved)

        let loaded = KeychainHelper.loadDate(key: testKey)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded!.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1.0)
    }

    func testSaveAndLoadData() {
        let data = "binary-data".data(using: .utf8)!
        let saved = KeychainHelper.save(key: testKey, data: data)
        XCTAssertTrue(saved)

        let loaded = KeychainHelper.load(key: testKey)
        XCTAssertEqual(loaded, data)
    }
}
