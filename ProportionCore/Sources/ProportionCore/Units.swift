import Foundation

/// Units are grouped into families whose members convert into one another
/// *exactly* — 3 tsp is precisely 1 tbsp, 1000 g is precisely 1 kg. Crossing
/// between families (cups → ml) is inherently approximate and only happens at
/// display time, never in stored data.
public enum UnitFamily: String, Codable, Sendable {
    case usVolume
    case metricVolume
    case metricMass
    case imperialMass
    case count

    /// Count units (cloves, slices, cans) never convert: 3 cloves is not 1 of
    /// anything else, so they are locked to the unit they were authored in.
    public var isConvertible: Bool { self != .count }
}

public enum MeasurementUnit: String, Codable, CaseIterable, Sendable {
    // US volume — base unit: teaspoon
    case teaspoon
    case tablespoon
    case cup
    case fluidOunce

    // Metric volume — base unit: millilitre
    case milliliter
    case liter

    // Metric mass — base unit: gram
    case gram
    case kilogram

    // Imperial mass — base unit: ounce
    case ounce
    case pound

    // Counts — never converted
    case piece
    case clove
    case slice
    case can
    case stick
    case bunch

    /// A bare number with no unit at all: "2 eggs".
    case unitless

    public var family: UnitFamily {
        switch self {
        case .teaspoon, .tablespoon, .cup, .fluidOunce: return .usVolume
        case .milliliter, .liter: return .metricVolume
        case .gram, .kilogram: return .metricMass
        case .ounce, .pound: return .imperialMass
        case .piece, .clove, .slice, .can, .stick, .bunch, .unitless: return .count
        }
    }

    /// Exact size of this unit in its family's base unit. Count units are 1.
    public var factorToBase: Rational {
        switch self {
        case .teaspoon: return 1
        case .tablespoon: return 3
        case .fluidOunce: return 6
        case .cup: return 48
        case .milliliter, .gram, .ounce: return 1
        case .liter, .kilogram: return 1000
        case .pound: return 16
        case .piece, .clove, .slice, .can, .stick, .bunch, .unitless: return 1
        }
    }

    public var abbreviation: String { displayName(plural: false) }

    public func displayName(plural: Bool) -> String {
        switch self {
        case .teaspoon: return "tsp"
        case .tablespoon: return "tbsp"
        case .cup: return plural ? "cups" : "cup"
        case .fluidOunce: return "fl oz"
        case .milliliter: return "ml"
        case .liter: return "L"
        case .gram: return "g"
        case .kilogram: return "kg"
        case .ounce: return "oz"
        case .pound: return "lb"
        case .piece: return plural ? "pieces" : "piece"
        case .clove: return plural ? "cloves" : "clove"
        case .slice: return plural ? "slices" : "slice"
        case .can: return plural ? "cans" : "can"
        case .stick: return plural ? "sticks" : "stick"
        case .bunch: return plural ? "bunches" : "bunch"
        case .unitless: return ""
        }
    }
}
