import Foundation
import ProportionCore

/// Model-backed macro estimate for ingredients the USDA database can't
/// resolve. Everything it returns is labelled *estimated* in the UI.
struct ClaudeNutritionEstimator: NutritionEstimator {
    var client: ClaudeClient
    var formatter = QuantityFormatter()

    private struct Payload: Decodable {
        var protein_g: Double
        var fat_g: Double
        var carbs_g: Double
        var assumed_grams: Double?
        var confidence: Double
    }

    private static let tool = ClaudeClient.Tool(
        name: "estimate_macros",
        description: "Report estimated macronutrients for the given amount of the ingredient.",
        inputSchema: Schema.object([
            "protein_g": Schema.number("Grams of protein in the stated amount (not per 100 g)."),
            "fat_g": Schema.number("Grams of fat in the stated amount."),
            "carbs_g": Schema.number("Grams of carbohydrate in the stated amount."),
            "assumed_grams": Schema.number("The weight in grams you assumed for the amount, if you had to infer it.", nullable: true),
            "confidence": Schema.number("0 to 1."),
        ])
    )

    private static let system = """
    You estimate macronutrients for a single recipe ingredient by calling estimate_macros exactly once. Report totals for the amount given, not per 100 g. If only a volume or count is given, infer a typical weight for that food and report it as assumed_grams. Use standard nutrition-database values for the closest generic food; do not guess wildly — if the ingredient is unidentifiable, return zeros with confidence 0.
    """

    func estimate(ingredient: Ingredient, grams: Double?) async throws -> Macros? {
        var description = "Ingredient: \(ingredient.name)"
        if let quantity = ingredient.quantity {
            description += "\nAmount: \(formatter.string(for: quantity))"
        } else if let descriptor = ingredient.descriptor {
            description += "\nAmount: \(descriptor)"
        }
        if let grams { description += "\nWeight: \(Int(grams.rounded())) g" }
        if let preparation = ingredient.preparation { description += "\nPreparation: \(preparation)" }

        let p = try await client.invokeTool(Payload.self, system: Self.system, content: [.text(description)], tool: Self.tool, effort: .low, maxTokens: 1024)
        guard p.confidence > 0 else { return nil }
        return Macros(protein: max(0, p.protein_g), fat: max(0, p.fat_g), carbs: max(0, p.carbs_g))
    }
}
