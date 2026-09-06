import Foundation

/// Macronutrients in grams. Calories are always derived, never stored, so the
/// three numbers can never disagree with the fourth.
public struct Macros: Hashable, Codable, Sendable {
    public var protein: Double
    public var fat: Double
    public var carbs: Double

    public init(protein: Double, fat: Double, carbs: Double) {
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
    }

    public static let zero = Macros(protein: 0, fat: 0, carbs: 0)

    /// Atwater factors: 4 kcal/g for protein and carbohydrate, 9 kcal/g for fat.
    public var calories: Double {
        protein * 4 + carbs * 4 + fat * 9
    }

    public func scaled(by factor: Double) -> Macros {
        Macros(protein: protein * factor, fat: fat * factor, carbs: carbs * factor)
    }

    public func divided(by divisor: Double) -> Macros {
        precondition(divisor != 0, "Cannot divide macros by zero")
        return scaled(by: 1 / divisor)
    }

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(protein: lhs.protein + rhs.protein,
               fat: lhs.fat + rhs.fat,
               carbs: lhs.carbs + rhs.carbs)
    }
}
