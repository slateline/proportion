import Foundation
import Observation
import ProportionCore

/// User preferences. Backed by UserDefaults; every property writes through
/// on set so views and services see one source of truth.
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unitSystem = Self.decodeUnitSystem(defaults.string(forKey: Keys.unitSystem))
        dietaryProfile = Self.decode(DietaryProfile.self, from: defaults.data(forKey: Keys.dietaryProfile)) ?? .empty
        dailyTargets = Self.decode(Macros.self, from: defaults.data(forKey: Keys.dailyTargets))
        useModelForParsing = defaults.object(forKey: Keys.useModel) as? Bool ?? true
        hasSeenNutritionDisclaimer = defaults.bool(forKey: Keys.seenDisclaimer)
        defaultServings = defaults.object(forKey: Keys.defaultServings) as? Int ?? 4
    }

    var unitSystem: QuantityFormatter.UnitSystem {
        didSet { defaults.set(Self.encodeUnitSystem(unitSystem), forKey: Keys.unitSystem) }
    }

    var dietaryProfile: DietaryProfile {
        didSet { defaults.set(Self.encode(dietaryProfile), forKey: Keys.dietaryProfile) }
    }

    /// Optional daily macro goals; used only to show progress on a recipe.
    var dailyTargets: Macros? {
        didSet { defaults.set(dailyTargets.flatMap(Self.encode), forKey: Keys.dailyTargets) }
    }

    /// When off, capture uses only the deterministic parsers and never
    /// sends text to the model — the privacy switch promised in Settings.
    var useModelForParsing: Bool {
        didSet { defaults.set(useModelForParsing, forKey: Keys.useModel) }
    }

    var hasSeenNutritionDisclaimer: Bool {
        didSet { defaults.set(hasSeenNutritionDisclaimer, forKey: Keys.seenDisclaimer) }
    }

    var defaultServings: Int {
        didSet { defaults.set(defaultServings, forKey: Keys.defaultServings) }
    }

    var formatter: QuantityFormatter { QuantityFormatter(unitSystem: unitSystem) }

    // MARK: Persistence helpers

    private enum Keys {
        static let unitSystem = "settings.unitSystem"
        static let dietaryProfile = "settings.dietaryProfile"
        static let dailyTargets = "settings.dailyTargets"
        static let useModel = "settings.useModelForParsing"
        static let seenDisclaimer = "settings.hasSeenNutritionDisclaimer"
        static let defaultServings = "settings.defaultServings"
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encodeUnitSystem(_ system: QuantityFormatter.UnitSystem) -> String {
        switch system {
        case .asAuthored: return "asAuthored"
        case .us: return "us"
        case .metric: return "metric"
        }
    }

    private static func decodeUnitSystem(_ raw: String?) -> QuantityFormatter.UnitSystem {
        switch raw {
        case "us": return .us
        case "metric": return .metric
        default: return .asAuthored
        }
    }
}
