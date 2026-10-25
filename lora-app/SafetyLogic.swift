import SwiftUI

// MARK: - Heat

enum HeatLevel: Int, Comparable {
    case safe, caution, extremeCaution, danger, extremeDanger

    static func < (a: HeatLevel, b: HeatLevel) -> Bool { a.rawValue < b.rawValue }

    /// NWS heat index categories (feels-like in °F)
    init(feelsLikeF f: Double) {
        switch f {
        case ..<80:  self = .safe
        case ..<90:  self = .caution
        case ..<103: self = .extremeCaution
        case ..<125: self = .danger
        default:     self = .extremeDanger
        }
    }

    var title: String {
        switch self {
        case .safe: return "Comfortable"
        case .caution: return "Caution"
        case .extremeCaution: return "Extreme Caution"
        case .danger: return "Danger"
        case .extremeDanger: return "Extreme Danger"
        }
    }

    var advice: String {
        switch self {
        case .safe: return "Conditions are comfortable."
        case .caution: return "Fatigue is possible with prolonged exposure. Drink water regularly."
        case .extremeCaution: return "Heat cramps and exhaustion are possible. Take shade breaks and hydrate."
        case .danger: return "Heat exhaustion is likely. Limit time outdoors and drink water often."
        case .extremeDanger: return "Extreme Danger - get out of the heat immediately."
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .caution: return .yellow
        case .extremeCaution: return .orange
        case .danger: return .red
        case .extremeDanger: return .purple
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.seal.fill"
        case .caution: return "sun.max.fill"
        case .extremeCaution: return "thermometer.sun.fill"
        case .danger: return "exclamationmark.triangle.fill"
        case .extremeDanger: return "light.beacon.max.fill"
        }
    }
}

/// NWS Rothfusz heat index. Inputs in °F and % relative humidity, returns °F.
func heatIndexF(tempF t: Double, humidity r: Double) -> Double {
    let simple = 0.5 * (t + 61.0 + (t - 68.0) * 1.2 + r * 0.094)
    if (simple + t) / 2.0 < 80.0 { return simple }

    var hi = -42.379
    hi += 2.04901523 * t
    hi += 10.14333127 * r
    hi -= 0.22475541 * t * r
    hi -= 0.00683783 * t * t
    hi -= 0.05481717 * r * r
    hi += 0.00122874 * t * t * r
    hi += 0.00085282 * t * r * r
    hi -= 0.00000199 * t * t * r * r

    if r < 13 && t >= 80 && t <= 112 {
        hi -= ((13 - r) / 4) * ((17 - abs(t - 95)) / 17).squareRoot()
    } else if r > 85 && t >= 80 && t <= 87 {
        hi += ((r - 85) / 10) * ((87 - t) / 5)
    }
    return hi
}

func celsiusToF(_ c: Double) -> Double { c * 9 / 5 + 32 }

// MARK: - UV

enum UVLevel {
    case low, moderate, high, veryHigh, extreme

    init(index: Double) {
        switch index {
        case ..<3:  self = .low
        case ..<6:  self = .moderate
        case ..<8:  self = .high
        case ..<11: self = .veryHigh
        default:    self = .extreme
        }
    }

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate (wear sunscreen)"
        case .high: return "High (cover up)"
        case .veryHigh: return "Very High (protect skin)"
        case .extreme: return "Extreme (avoid the sun)"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .extreme: return .purple
        }
    }
}

/// GUVA-S12SD boards output roughly 100 mV per UV index point.
/// Adjust these after calibrating against a known UV reading.
let uvMillivoltsPerIndex = 100.0
let uvOffsetMillivolts = 0.0
