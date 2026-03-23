import XCTest
@testable import CafePulse

final class AppSettingsTests: XCTestCase {

    // MARK: - StartSessionDraft

    func testNormalizedCafeNameTrimsWhitespace() {
        var draft = StartSessionDraft()
        draft.cafeName = "  Blue Bottle  "
        XCTAssertEqual(draft.normalizedCafeName, "Blue Bottle")
    }

    func testNormalizedCafeNameEmptyString() {
        let draft = StartSessionDraft()
        XCTAssertEqual(draft.normalizedCafeName, "")
    }

    func testNormalizedLocationNilWhenEmpty() {
        var draft = StartSessionDraft()
        draft.location = "   "
        XCTAssertNil(draft.normalizedLocation)
    }

    func testNormalizedLocationValueWhenPresent() {
        var draft = StartSessionDraft()
        draft.location = " Berlin "
        XCTAssertEqual(draft.normalizedLocation, "Berlin")
    }

    func testParsedTagsSplitsAndTrims() {
        var draft = StartSessionDraft()
        draft.tagsText = " morning , busy,  chill "
        XCTAssertEqual(draft.parsedTags, ["morning", "busy", "chill"])
    }

    func testParsedTagsEmptyString() {
        let draft = StartSessionDraft()
        XCTAssertEqual(draft.parsedTags, [])
    }

    func testParsedTagsFiltersEmptyEntries() {
        var draft = StartSessionDraft()
        draft.tagsText = "morning,,, ,chill"
        XCTAssertEqual(draft.parsedTags, ["morning", "chill"])
    }

    // MARK: - CrowdEstimateDraft

    func testResolvedPeopleCountNilWhenToggleOff() {
        var draft = CrowdEstimateDraft()
        draft.includePeopleCount = false
        draft.peopleCount = 15
        XCTAssertNil(draft.resolvedPeopleCount)
    }

    func testResolvedPeopleCountValueWhenToggleOn() {
        var draft = CrowdEstimateDraft()
        draft.includePeopleCount = true
        draft.peopleCount = 15
        XCTAssertEqual(draft.resolvedPeopleCount, 15)
    }

    func testResolvedPeopleCountClampsNegative() {
        var draft = CrowdEstimateDraft()
        draft.includePeopleCount = true
        draft.peopleCount = -5
        XCTAssertEqual(draft.resolvedPeopleCount, 0)
    }

    // MARK: - AppSettings defaults

    func testDefaultSettings() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.sampleIntervalSeconds, 5)
        XCTAssertEqual(settings.crowdPromptIntervalSeconds, 900) // 15 * 60
    }
}
