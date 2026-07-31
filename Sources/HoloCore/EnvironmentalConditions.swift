import Foundation

public enum EnvironmentalTopic: String, CaseIterable, Codable, Sendable, Identifiable {
    case airQuality
    case weatherAndUV
    case environmentalAlerts
    case waterAndRain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .airQuality: return "Air Quality"
        case .weatherAndUV: return "Weather & UV"
        case .environmentalAlerts: return "Environmental Alerts"
        case .waterAndRain: return "Water & Rain"
        }
    }

    public var question: String {
        switch self {
        case .airQuality: return "Is the air healthy?"
        case .weatherAndUV: return "What is it like outside?"
        case .environmentalAlerts: return "Is anything hazardous nearby?"
        case .waterAndRain: return "Could rain or flooding affect me?"
        }
    }

    public var symbolName: String {
        switch self {
        case .airQuality: return "aqi.medium"
        case .weatherAndUV: return "sun.max"
        case .environmentalAlerts: return "exclamationmark.triangle"
        case .waterAndRain: return "drop"
        }
    }
}

public enum USAirQualityCategory: String, Codable, Sendable, Equatable {
    case good
    case moderate
    case unhealthyForSensitiveGroups
    case unhealthy
    case veryUnhealthy
    case hazardous

    public init(aqi: Int) {
        switch aqi {
        case ...50: self = .good
        case 51...100: self = .moderate
        case 101...150: self = .unhealthyForSensitiveGroups
        case 151...200: self = .unhealthy
        case 201...300: self = .veryUnhealthy
        default: self = .hazardous
        }
    }

    public var title: String {
        switch self {
        case .good: return "Good"
        case .moderate: return "Moderate"
        case .unhealthyForSensitiveGroups: return "Unhealthy for sensitive groups"
        case .unhealthy: return "Unhealthy"
        case .veryUnhealthy: return "Very unhealthy"
        case .hazardous: return "Hazardous"
        }
    }

    public var guidance: String {
        switch self {
        case .good:
            return "Air pollution is low. Normal outdoor activity is appropriate."
        case .moderate:
            return "Air is acceptable for most people. Unusually sensitive people may want to reduce prolonged outdoor activity."
        case .unhealthyForSensitiveGroups:
            return "Children, older adults, and people with heart or lung conditions should reduce prolonged outdoor activity."
        case .unhealthy:
            return "Everyone should consider reducing prolonged or strenuous outdoor activity."
        case .veryUnhealthy:
            return "Avoid strenuous outdoor activity and follow local health guidance."
        case .hazardous:
            return "Stay indoors when practical and follow official emergency guidance."
        }
    }
}

public enum UVRisk: String, Codable, Sendable, Equatable {
    case low, moderate, high, veryHigh, extreme

    public init(index: Double) {
        switch index {
        case ..<3: self = .low
        case 3..<6: self = .moderate
        case 6..<8: self = .high
        case 8..<11: self = .veryHigh
        default: self = .extreme
        }
    }

    public var title: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very high"
        case .extreme: return "Extreme"
        }
    }

    public var guidance: String {
        switch self {
        case .low: return "Sun protection is usually not needed for short periods outside."
        case .moderate: return "Use sunscreen and seek shade around midday."
        case .high: return "Use sunscreen, protective clothing, and shade."
        case .veryHigh: return "Limit midday sun and use strong sun protection."
        case .extreme: return "Avoid midday sun when possible and use full sun protection."
        }
    }
}

public struct EnvironmentalReading: Codable, Equatable, Sendable, Identifiable {
    public let topic: EnvironmentalTopic
    public let headline: String
    public let value: String
    public let explanation: String
    public let guidance: String
    public let spokenSummary: String

    public var id: EnvironmentalTopic { topic }

    public init(
        topic: EnvironmentalTopic,
        headline: String,
        value: String,
        explanation: String,
        guidance: String,
        spokenSummary: String
    ) {
        self.topic = topic
        self.headline = headline
        self.value = value
        self.explanation = explanation
        self.guidance = guidance
        self.spokenSummary = spokenSummary
    }
}

public struct EnvironmentalSnapshot: Codable, Equatable, Sendable {
    public let locationName: String
    public let updatedAt: Date
    public let isDemonstration: Bool
    public let readings: [EnvironmentalReading]

    public init(locationName: String, updatedAt: Date, isDemonstration: Bool, readings: [EnvironmentalReading]) {
        self.locationName = locationName
        self.updatedAt = updatedAt
        self.isDemonstration = isDemonstration
        self.readings = readings
    }

    public func reading(for topic: EnvironmentalTopic) -> EnvironmentalReading? {
        readings.first { $0.topic == topic }
    }

    public static func demonstration(now: Date = Date()) -> EnvironmentalSnapshot {
        let aqi = 67
        let airCategory = USAirQualityCategory(aqi: aqi)
        let uv = 8.0
        let uvRisk = UVRisk(index: uv)

        return EnvironmentalSnapshot(
            locationName: "Example location",
            updatedAt: now,
            isDemonstration: true,
            readings: [
                EnvironmentalReading(
                    topic: .airQuality,
                    headline: airCategory.title,
                    value: "AQI \(aqi)",
                    explanation: "AQI means Air Quality Index. It turns several pollution measurements into one public-health scale. The main example pollutant is PM2.5: tiny particles that can travel deep into the lungs.",
                    guidance: airCategory.guidance,
                    spokenSummary: "Air quality is \(airCategory.title.lowercased()). The Air Quality Index is \(aqi). \(airCategory.guidance)"
                ),
                EnvironmentalReading(
                    topic: .weatherAndUV,
                    headline: "Warm with very high UV",
                    value: "84°F · UV \(Int(uv))",
                    explanation: "The UV Index describes the strength of skin-damaging ultraviolet radiation from the sun. Higher values mean sunburn can happen faster.",
                    guidance: uvRisk.guidance,
                    spokenSummary: "It is 84 degrees. The UV Index is \(Int(uv)), which is \(uvRisk.title.lowercased()). \(uvRisk.guidance)"
                ),
                EnvironmentalReading(
                    topic: .environmentalAlerts,
                    headline: "No active alerts",
                    value: "All clear",
                    explanation: "This zone will summarize official air-quality, heat, smoke, severe-weather, and flood notices for the selected location.",
                    guidance: "Continue to check conditions before extended outdoor activity.",
                    spokenSummary: "There are no active environmental alerts in this demonstration."
                ),
                EnvironmentalReading(
                    topic: .waterAndRain,
                    headline: "Low flood concern",
                    value: "0.10 in rain",
                    explanation: "Recent and forecast rainfall can indicate changing runoff and flood risk. It does not describe drinking-water quality.",
                    guidance: "No rain-related action is suggested by this demonstration.",
                    spokenSummary: "Rainfall and flood concern are low. This reading does not describe drinking-water quality."
                )
            ]
        )
    }
}

public extension DeskZone {
    var environmentalTopic: EnvironmentalTopic {
        switch self {
        case .leftTop: return .airQuality
        case .leftBottom: return .weatherAndUV
        case .rightTop: return .environmentalAlerts
        case .rightBottom: return .waterAndRain
        }
    }
}
