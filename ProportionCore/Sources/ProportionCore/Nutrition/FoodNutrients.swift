import Foundation

/// Nutrition for a food as a database reports it: per 100 g.
public struct FoodNutrients: Hashable, Codable, Sendable {
    public var description: String
    /// The database's own identifier, e.g. a FoodData Central FDC ID.
    public var sourceID: String?
    public var per100g: Macros

    public init(description: String, sourceID: String? = nil, per100g: Macros) {
        self.description = description
        self.sourceID = sourceID
        self.per100g = per100g
    }

    public func macros(forGrams grams: Double) -> Macros {
        per100g.scaled(by: grams / 100)
    }
}

/// A nutrition database. The USDA client is the real one; tests use an
/// in-memory table.
public protocol NutrientSource: Sendable {
    /// The best match for a canonical ingredient name, or nil if none.
    func lookup(_ query: String) async throws -> FoodNutrients?
}

/// The model-backed fallback for ingredients no database resolves. Anything
/// it returns is marked *estimated* in the UI.
public protocol NutritionEstimator: Sendable {
    func estimate(ingredient: Ingredient, grams: Double?) async throws -> Macros?
}

public struct InMemoryNutrientSource: NutrientSource {
    public var table: [String: FoodNutrients]

    public init(_ table: [String: FoodNutrients] = [:]) {
        var lowered: [String: FoodNutrients] = [:]
        for (key, value) in table { lowered[key.lowercased()] = value }
        self.table = lowered
    }

    public func lookup(_ query: String) async throws -> FoodNutrients? {
        table[query.lowercased()]
    }
}
