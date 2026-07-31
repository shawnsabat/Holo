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
}
