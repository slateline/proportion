import Foundation

public enum ScalingError: Error, Equatable, Sendable {
    case servingsOutOfRange(Int)
    case noNutritionData
    case invalidProteinTarget
}

/// A caveat attached to a scaled ingredient.
public enum ScalingNote: Hashable, Codable, Sendable {
    /// The ingredient is flagged as not scaling linearly. It was scaled
    /// anyway; the cook should check it.
    case adjustByTaste

    public var message: String {
        switch self {
        case .adjustByTaste: return "Seasoning may need adjusting by taste"
        }
    }
}

public struct ScaledIngredient: Identifiable, Hashable, Sendable {
    public let ingredient: Ingredient
    /// The scaled amount, or nil when the ingredient has no numeric quantity
    /// (in which case `ingredient.descriptor` is shown unchanged).
    public let quantity: Quantity?
    public let note: ScalingNote?

    public init(ingredient: Ingredient, quantity: Quantity?, note: ScalingNote?) {
        self.ingredient = ingredient
        self.quantity = quantity
        self.note = note
    }

    public var id: UUID { ingredient.id }
}

/// A recipe viewed at a different serving count. Holds the untouched base
/// recipe and the exact factor applied to it; nothing here is ever written
/// back to the base.
public struct ScaledRecipe: Hashable, Sendable {
    public let base: Recipe
    public let factor: Rational
    public let ingredients: [ScaledIngredient]

    /// May be fractional when scaling by a protein target.
    public var servings: Rational {
        Rational(base.baseServings) * factor
    }

    public var totalMacros: Macros? {
        base.totalMacros?.scaled(by: factor.doubleValue)
    }

    /// Invariant: scaling changes how much food there is, never what is in a
    /// serving. Computed straight from the base so it cannot drift.
    public var perServingMacros: Macros? {
        base.perServingMacros
    }
}

public enum ScalingEngine {
    public static let servingRange: ClosedRange<Int> = 1...50

    /// Scales to an exact serving count within `servingRange`.
    public static func scale(_ recipe: Recipe, toServings target: Int) throws -> ScaledRecipe {
        guard servingRange.contains(target) else {
            throw ScalingError.servingsOutOfRange(target)
        }
        return scale(recipe, by: Rational(target, recipe.baseServings))
    }

    /// Scales by an arbitrary positive factor. Every scaling operation goes
    /// through here and always starts from the base recipe, which is what
    /// makes repeated adjustment drift-free by construction.
    public static func scale(_ recipe: Recipe, by factor: Rational) -> ScaledRecipe {
        precondition(factor.numerator > 0, "Scale factor must be positive")
        let isIdentity = factor == .one
        let scaled = recipe.ingredients.map { ingredient -> ScaledIngredient in
            let quantity = ingredient.quantity?.scaled(by: factor)
            // Only warn about non-linear items when something actually changed.
            let note: ScalingNote? =
                (quantity != nil && !ingredient.isScalable && !isIdentity) ? .adjustByTaste : nil
            return ScaledIngredient(ingredient: ingredient, quantity: quantity, note: note)
        }
        return ScaledRecipe(base: recipe, factor: factor, ingredients: scaled)
    }

    /// Scales the whole recipe so its total protein reaches `grams`. The
    /// resulting serving count may be fractional and must land inside
    /// `servingRange`.
    public static func scale(_ recipe: Recipe, toTotalProtein grams: Double) throws -> ScaledRecipe {
        guard let macros = recipe.totalMacros, macros.protein > 0 else {
            throw ScalingError.noNutritionData
        }
        guard grams > 0, grams.isFinite else {
            throw ScalingError.invalidProteinTarget
        }
        let factor = Rational(approximating: grams / macros.protein, maxDenominator: 100)
        let servings = Rational(recipe.baseServings) * factor
        let lower = Rational(servingRange.lowerBound)
        let upper = Rational(servingRange.upperBound)
        guard servings >= lower, servings <= upper else {
            throw ScalingError.servingsOutOfRange(Int(servings.doubleValue.rounded()))
        }
        return scale(recipe, by: factor)
    }
}
