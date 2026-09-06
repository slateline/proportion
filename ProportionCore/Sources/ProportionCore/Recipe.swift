import Foundation

/// How much of a recipe's nutrition came from a real database lookup versus a
/// model estimate. Surfaced on every recipe so the user knows what to trust.
public enum NutritionConfidence: String, Codable, Sendable {
    case verified
    case partiallyEstimated
    case estimated
    case unknown
}

/// A saved recipe at its authored serving count. Scaling never mutates this;
/// see `ScalingEngine`, which produces a derived `ScaledRecipe`.
public struct Recipe: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceURL: URL?
    public var sourceAttribution: String?

    /// The serving count the ingredient amounts were written for. Always ≥ 1.
    public var baseServings: Int

    public var ingredients: [Ingredient]
    public var steps: [String]
    public var prepMinutes: Int?
    public var cookMinutes: Int?

    /// Nutrition for the *whole* recipe at `baseServings`.
    public var totalMacros: Macros?
    public var nutritionConfidence: NutritionConfidence

    /// 0…1 confidence reported by the parser, when the recipe came from one.
    public var parseConfidence: Double?

    public var tags: Set<String>
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL? = nil,
        sourceAttribution: String? = nil,
        baseServings: Int,
        ingredients: [Ingredient] = [],
        steps: [String] = [],
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        totalMacros: Macros? = nil,
        nutritionConfidence: NutritionConfidence = .unknown,
        parseConfidence: Double? = nil,
        tags: Set<String> = [],
        createdAt: Date = Date()
    ) {
        precondition(baseServings >= 1, "A recipe must serve at least one")
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceAttribution = sourceAttribution
        self.baseServings = baseServings
        self.ingredients = ingredients
        self.steps = steps
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.totalMacros = totalMacros
        self.nutritionConfidence = nutritionConfidence
        self.parseConfidence = parseConfidence
        self.tags = tags
        self.createdAt = createdAt
    }

    /// Nutrition for one serving. This is the quantity that stays constant as
    /// the recipe is scaled.
    public var perServingMacros: Macros? {
        totalMacros?.divided(by: Double(baseServings))
    }

    public var totalMinutes: Int? {
        switch (prepMinutes, cookMinutes) {
        case (nil, nil): return nil
        case let (p?, c?): return p + c
        case let (p?, nil): return p
        case let (nil, c?): return c
        }
    }
}
