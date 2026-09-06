import Foundation

/// The single intermediate form every capture path produces — JSON-LD from a
/// web page, pasted text, OCR, a model parse, the manual form. The app turns a
/// draft into a `Recipe` only after the user has seen it on the parse-review
/// screen; nothing goes into the library unreviewed.
public struct RecipeDraft: Hashable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        case jsonLD
        case pastedText
        case ocr
        case llm
        case shareExtension
        case manual
    }

    public var title: String
    public var sourceURL: URL?
    public var sourceAttribution: String?
    public var imageURL: URL?

    /// Nil when the source didn't say. `makeRecipe` assumes a default and
    /// records a warning so the review screen can flag it.
    public var servings: Int?

    /// Raw ingredient lines as the source gave them.
    public var ingredientLines: [String]

    /// Structured ingredients, when the source could provide them directly.
    /// When nil, `makeRecipe` runs `ingredientLines` through the line parser.
    public var ingredients: [Ingredient]?

    public var steps: [String]
    public var prepMinutes: Int?
    public var cookMinutes: Int?

    /// Sources that carry nutrition (schema.org, a model estimate) report it
    /// per serving; the recipe stores the whole-recipe total.
    public var perServingMacros: Macros?
    public var nutritionConfidence: NutritionConfidence

    public var parseConfidence: Double?
    public var source: Source

    /// Things the review screen should draw attention to.
    public var warnings: [String]

    public init(
        title: String,
        sourceURL: URL? = nil,
        sourceAttribution: String? = nil,
        imageURL: URL? = nil,
        servings: Int? = nil,
        ingredientLines: [String] = [],
        ingredients: [Ingredient]? = nil,
        steps: [String] = [],
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        perServingMacros: Macros? = nil,
        nutritionConfidence: NutritionConfidence = .unknown,
        parseConfidence: Double? = nil,
        source: Source,
        warnings: [String] = []
    ) {
        self.title = title
        self.sourceURL = sourceURL
        self.sourceAttribution = sourceAttribution
        self.imageURL = imageURL
        self.servings = servings
        self.ingredientLines = ingredientLines
        self.ingredients = ingredients
        self.steps = steps
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.perServingMacros = perServingMacros
        self.nutritionConfidence = nutritionConfidence
        self.parseConfidence = parseConfidence
        self.source = source
        self.warnings = warnings
    }

    public static let assumedServings = 4

    /// Whether there is enough here to be worth showing the user at all.
    public var isUsable: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (!ingredientLines.isEmpty || !(ingredients ?? []).isEmpty)
    }

    /// Structures, tags, and assembles the draft into a recipe. Pure and
    /// deterministic: the same draft always yields the same recipe.
    public func makeRecipe(
        lineParser: IngredientLineParser = IngredientLineParser(),
        taxonomy: IngredientTaxonomy = .standard
    ) -> (recipe: Recipe, warnings: [String]) {
        var warnings = self.warnings

        let structured = ingredients ?? lineParser.parse(lines: ingredientLines)
        let tagged = structured.map(taxonomy.tagged)

        let baseServings: Int
        if let servings, servings >= 1 {
            baseServings = servings
        } else {
            baseServings = Self.assumedServings
            warnings.append("Serving count not found — assumed \(Self.assumedServings). Check it before saving.")
        }

        let unparsed = tagged.filter { $0.quantity == nil && $0.descriptor == nil }
        if !unparsed.isEmpty {
            warnings.append("\(unparsed.count) ingredient line\(unparsed.count == 1 ? "" : "s") could not be given a quantity.")
        }

        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: sourceURL,
            sourceAttribution: sourceAttribution,
            baseServings: baseServings,
            ingredients: tagged,
            steps: steps,
            prepMinutes: prepMinutes,
            cookMinutes: cookMinutes,
            totalMacros: perServingMacros?.scaled(by: Double(baseServings)),
            nutritionConfidence: perServingMacros == nil ? .unknown : nutritionConfidence,
            parseConfidence: parseConfidence
        )
        return (recipe, warnings)
    }
}
