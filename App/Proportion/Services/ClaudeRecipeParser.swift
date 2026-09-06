import Foundation
import ProportionCore

/// The model-backed recipe parser, used only when the deterministic parsers
/// can't structure the text confidently. It asks for one strict tool call
/// and converts it to a `RecipeDraft`; quantities the model gives as numbers
/// are pinned to exact rationals, and any line it can't structure is run
/// back through the deterministic line parser so nothing is lost.
struct ClaudeRecipeParser: Sendable {
    var client: ClaudeClient
    var lineParser = IngredientLineParser()

    private struct Payload: Decodable {
        struct Line: Decodable {
            var text: String
            var name: String?
            var quantity: Double?
            var unit: String?
            var preparation: String?
            var scalable: Bool
        }
        var is_recipe: Bool
        var title: String
        var servings: Int?
        var prep_minutes: Int?
        var cook_minutes: Int?
        var ingredients: [Line]
        var steps: [String]
        var confidence: Double
    }

    private static let unitValues = MeasurementUnit.allCases.map(\.rawValue)

    private static let tool = ClaudeClient.Tool(
        name: "save_recipe",
        description: "Record the recipe extracted from the provided text or images.",
        inputSchema: JSONSchema.object([
            "is_recipe": JSONSchema.boolean("False if the input does not contain a cooking recipe."),
            "title": JSONSchema.string("The recipe's name. Empty string if is_recipe is false."),
            "servings": JSONSchema.integer("How many servings the ingredient amounts make, only if stated.", nullable: true),
            "prep_minutes": JSONSchema.integer("Preparation time in minutes, only if stated.", nullable: true),
            "cook_minutes": JSONSchema.integer("Cooking time in minutes, only if stated.", nullable: true),
            "ingredients": JSONSchema.array(of: JSONSchema.object([
                "text": JSONSchema.string("The ingredient line exactly as written in the source."),
                "name": JSONSchema.string("Canonical item name, e.g. 'all-purpose flour', 'chicken thigh'.", nullable: true),
                "quantity": JSONSchema.number("Numeric amount as a decimal (1.5 for 1 ½). Null for 'to taste' or unknown.", nullable: true),
                "unit": JSONSchema.string("Unit of the quantity. Use 'unitless' for bare counts such as '2 eggs'.", nullable: true, values: unitValues),
                "preparation": JSONSchema.string("Preparation note such as 'finely diced', or the phrase for a non-numeric amount such as 'to taste'.", nullable: true),
                "scalable": JSONSchema.boolean("False for leavening, salt, spices, and anything that does not scale linearly with servings."),
            ]), description: "Every ingredient line, in order."),
            "steps": JSONSchema.array(of: JSONSchema.string("One instruction step."), description: "Instructions in order, one step per entry."),
            "confidence": JSONSchema.number("0 to 1: how completely and unambiguously the source specified the recipe."),
        ])
    )

    private static let system = """
    You extract cooking recipes into structured data. Always respond by calling the save_recipe tool exactly once.

    Rules:
    - Extract only what is present. Never invent quantities, servings, times, or steps that the source does not state.
    - Keep each ingredient's `text` exactly as written. Split it into a canonical `name`, a decimal `quantity`, a `unit` from the allowed list, and a `preparation` note.
    - Use unit 'unitless' for bare counts ("2 eggs", "1 onion"). Non-numeric amounts ("to taste", "a pinch") get quantity null and the phrase in `preparation`.
    - Set scalable=false for leavening, salt, strong spices, and anything that does not scale linearly.
    - If the input is not a recipe, set is_recipe=false, confidence=0, and leave the lists empty.
    - `confidence` reflects how completely the source specified the recipe, not how confident you are in your reading.
    """

    func parse(text: String, sourceURL: URL?, hint: String? = nil) async throws -> RecipeDraft {
        var prompt = "Extract the recipe from the following text."
        if let hint, !hint.isEmpty { prompt += " Context: \(hint)" }
        prompt += "\n\n<text>\n\(text)\n</text>"
        let payload = try await client.invokeTool(Payload.self, system: Self.system, content: [.text(prompt)], tool: Self.tool, effort: .medium)
        return try draft(from: payload, sourceURL: sourceURL)
    }

    func parse(images: [Data], hint: String? = nil) async throws -> RecipeDraft {
        var content: [ClaudeClient.Content] = images.map { .jpeg($0) }
        var prompt = "Extract the recipe shown in the image\(images.count > 1 ? "s" : "")."
        if let hint, !hint.isEmpty { prompt += " Context: \(hint)" }
        content.append(.text(prompt))
        let payload = try await client.invokeTool(Payload.self, system: Self.system, content: content, tool: Self.tool, effort: .medium)
        return try draft(from: payload, sourceURL: nil)
    }

    enum ParseError: LocalizedError {
        case notARecipe
        var errorDescription: String? { "That doesn't look like a recipe." }
    }

    private func draft(from payload: Payload, sourceURL: URL?) throws -> RecipeDraft {
        guard payload.is_recipe, !payload.ingredients.isEmpty else { throw ParseError.notARecipe }

        let ingredients: [Ingredient] = payload.ingredients.map { line in
            let fallback = lineParser.parse(line.text)
            var ingredient = fallback
            if let name = line.name, !name.isEmpty { ingredient.name = name }
            if let quantity = line.quantity, quantity > 0 {
                let unit = line.unit.flatMap(MeasurementUnit.init(rawValue:)) ?? .unitless
                ingredient.quantity = Quantity(Rational(approximating: quantity, maxDenominator: 32), unit)
                ingredient.descriptor = nil
            } else if ingredient.quantity == nil, ingredient.descriptor == nil,
                      let preparation = line.preparation, !preparation.isEmpty {
                ingredient.descriptor = preparation
            }
            if let preparation = line.preparation, !preparation.isEmpty, ingredient.descriptor != preparation {
                ingredient.preparation = preparation
            }
            ingredient.isScalable = line.scalable && fallback.isScalable
            return ingredient
        }

        var warnings: [String] = []
        if payload.steps.isEmpty { warnings.append("No instructions were found.") }
        if payload.confidence < 0.5 { warnings.append("The source was ambiguous — check every field.") }

        return RecipeDraft(
            title: payload.title,
            sourceURL: sourceURL,
            sourceAttribution: sourceURL?.host,
            servings: payload.servings,
            ingredientLines: payload.ingredients.map(\.text),
            ingredients: ingredients,
            steps: payload.steps,
            prepMinutes: payload.prep_minutes,
            cookMinutes: payload.cook_minutes,
            parseConfidence: payload.confidence,
            source: .llm,
            warnings: warnings)
    }
}
