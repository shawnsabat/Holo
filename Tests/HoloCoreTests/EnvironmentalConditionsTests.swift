import XCTest
@testable import HoloCore

final class EnvironmentalConditionsTests: XCTestCase {
    func testAQICategoryBoundaries() {
        XCTAssertEqual(USAirQualityCategory(aqi: 50), .good)
        XCTAssertEqual(USAirQualityCategory(aqi: 51), .moderate)
        XCTAssertEqual(USAirQualityCategory(aqi: 100), .moderate)
        XCTAssertEqual(USAirQualityCategory(aqi: 101), .unhealthyForSensitiveGroups)
        XCTAssertEqual(USAirQualityCategory(aqi: 151), .unhealthy)
        XCTAssertEqual(USAirQualityCategory(aqi: 201), .veryUnhealthy)
        XCTAssertEqual(USAirQualityCategory(aqi: 301), .hazardous)
    }

    func testUVRiskBoundaries() {
        XCTAssertEqual(UVRisk(index: 2.9), .low)
        XCTAssertEqual(UVRisk(index: 3), .moderate)
        XCTAssertEqual(UVRisk(index: 6), .high)
        XCTAssertEqual(UVRisk(index: 8), .veryHigh)
        XCTAssertEqual(UVRisk(index: 11), .extreme)
    }

    func testEachDeskZoneMapsToOneEnvironmentalTopic() {
        XCTAssertEqual(Set(DeskZone.allCases.map(\.environmentalTopic)), Set(EnvironmentalTopic.allCases))
    }

    func testDemonstrationIsClearlyMarkedAndComplete() {
        let snapshot = EnvironmentalSnapshot.demonstration(now: Date(timeIntervalSince1970: 0))

        XCTAssertTrue(snapshot.isDemonstration)
        XCTAssertEqual(snapshot.readings.count, EnvironmentalTopic.allCases.count)
        XCTAssertTrue(snapshot.readings.allSatisfy { !$0.guidance.isEmpty && !$0.spokenSummary.isEmpty })
        XCTAssertTrue(snapshot.reading(for: .airQuality)?.explanation.contains("AQI means Air Quality Index") == true)
    }

    func testSnapshotCanBeCachedAndRestored() throws {
        let original = EnvironmentalSnapshot.demonstration(now: Date(timeIntervalSince1970: 123))
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(EnvironmentalSnapshot.self, from: data)

        XCTAssertEqual(restored, original)
    }

    func testActiveAlertsPrioritizeSeverityAndLimitSpokenList() {
        let reading = EnvironmentalAlertInterpreter.reading(for: .active([
            EnvironmentalAlert(event: "Heat Advisory", severity: "Moderate"),
            EnvironmentalAlert(event: "Extreme Heat Warning", headline: "Dangerous heat expected", severity: "Severe"),
            EnvironmentalAlert(event: "Flood Watch", severity: "Moderate")
        ]))

        XCTAssertEqual(reading.headline, "Extreme Heat Warning")
        XCTAssertEqual(reading.value, "3 active alerts")
        XCTAssertEqual(reading.explanation, "Dangerous heat expected")
        XCTAssertTrue(reading.spokenSummary.contains("1 additional alert"))
    }

    func testEmptyActiveAlertListSafelyBecomesNone() {
        let reading = EnvironmentalAlertInterpreter.reading(for: .active([]))
        XCTAssertEqual(reading.headline, "No active NWS alerts")
    }

    func testUnavailableAlertsNeverClaimAllClear() {
        let reading = EnvironmentalAlertInterpreter.reading(for: .unavailable)
        XCTAssertEqual(reading.headline, "Alerts temporarily unavailable")
        XCTAssertTrue(reading.explanation.contains("does not mean conditions are safe"))
        XCTAssertFalse(reading.spokenSummary.lowercased().contains("no active alerts"))
    }

    func testOutsideCoverageDirectsUserToRegionalAuthority() {
        let reading = EnvironmentalAlertInterpreter.reading(for: .outsideCoverage)
        XCTAssertEqual(reading.headline, "Outside NWS coverage")
        XCTAssertTrue(reading.guidance.contains("local national weather service"))
    }
}
