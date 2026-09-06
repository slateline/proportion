import Foundation

/// One ingredient's contribution to a recipe's nutrition.
public struct IngredientNutrition: Identifiable, Hashable, Sendable {
    public enum Status: String, Hashable, Codable, Sendable {
        /// Weight known and a database record matched.
        case verified
        /// Came from the model fallback.
        case estimated
        /// Nothing could price it. Shown, not counted.
        case unresolved
    }

    public let id: UUID
    public let name: String
    public let grams: Double?
    public let macros: Macros?
    public let status: Status
    public let matchedFood: String?

    /// True for "salt to taste"-style lines with no amount at all. They can't
    /// be priced and don't count against confidence.
    public let isNegligible: Bool
}

public struct NutritionReport: Hashable, Sendable {
    public let items: [IngredientNutrition]

    public var total: Macros {
        items.compactMap(\.macros).reduce(.zero, +)
    }

    public var unresolved: [IngredientNutrition] {
        items.filter { $0.status == .unresolved && !$0.isNegligible }
    }

    /// The honest headline for the recipe. Verified only when *every*
    /// priced ingredient matched a database record.
    public var confidence: NutritionConfidence {
        let priced = items.filter { !$0.isNegligible }
        guard priced.contains(where: { $0.macros != nil }) else { return .unknown }
        if priced.allSatisfy({ $0.status == .verified }) { return .verified }
        if priced.contains(where: { $0.status == .verified }) { return .partiallyEstimated }
        return .estimated
    }
}

/// Sums a recipe's nutrition from its ingredients: resolve each to grams,
/// look it up, fall back to the estimator, and report exactly how much of
/// the answer is trustworthy.
public struct NutritionCalculator: Sendable {
    public var source: any NutrientSource
    public var estimator: (any NutritionEstimator)?
    public var gramEstimator: GramEstimator
    public var taxonomy: IngredientTaxonomy

    public init(
        source: any NutrientSource,
        estimator: (any NutritionEstimator)? = nil,
        gramEstimator: GramEstimator = GramEstimator(),
        taxonomy: IngredientTaxonomy = .standard
    ) {
        self.source = source
        self.estimator = estimator
        self.gramEstimator = gramEstimator
        self.taxonomy = taxonomy
    }

    public func report(for recipe: Recipe) async -> NutritionReport {
        var items: [IngredientNutrition] = []
        for ingredient in recipe.ingredients {
            items.append(await price(ingredient))
        }
        return NutritionReport(items: items)
    }

    /// A recipe updated with the report's totals and confidence.
    public func apply(_ report: NutritionReport, to recipe: Recipe) -> Recipe {
        var updated = recipe
        updated.totalMacros = report.confidence == .unknown ? nil : report.total
        updated.nutritionConfidence = report.confidence
        return updated
    }

    private func price(_ ingredient: Ingredient) async -> IngredientNutrition {
        let negligible = ingredient.quantity == nil && ingredient.grams == nil
        let grams = gramEstimator.grams(for: ingredient)
        let canonical = taxonomy.canonicalName(for: ingredient.name)

        if let grams, let food = try? await source.lookup(canonical) {
            return IngredientNutrition(
                id: ingredient.id, name: ingredient.name, grams: grams,
                macros: food.macros(forGrams: grams), status: .verified,
                matchedFood: food.description, isNegligible: negligible)
        }

        if !negligible, let estimator, let macros = try? await estimator.estimate(ingredient: ingredient, grams: grams) {
            return IngredientNutrition(
                id: ingredient.id, name: ingredient.name, grams: grams,
                macros: macros, status: .estimated, matchedFood: nil, isNegligible: negligible)
        }

        return IngredientNutrition(
            id: ingredient.id, name: ingredient.name, grams: grams,
            macros: nil, status: .unresolved, matchedFood: nil, isNegligible: negligible)
    }
}
