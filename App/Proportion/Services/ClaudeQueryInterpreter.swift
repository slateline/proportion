import Foundation
import ProportionCore

/// Turns a chat message into a `SearchQuery` with the model. The model's
/// only job is interpretation — it never sees the library and never picks
/// results. Wrapped in `FallbackQueryInterpreter` so the keyword parser
/// takes over offline.
struct ClaudeQueryInterpreter: QueryInterpreter {
    var client: ClaudeClient

    private struct Payload: Decodable {
        var text: String?
        var include_ingredients: [String]
        var exclude_ingredients: [String]
        var min_protein: Double?
        var max_protein: Double?
        var min_carbs: Double?
        var max_carbs: Double?
        var min_fat: Double?
        var max_fat: Double?
        var max_calories: Double?
        var max_minutes: Int?
        var tags: [String]
        var meal_type: String?
    }

    private static let tool = ClaudeClient.Tool(
        name: "set_search_query",
        description: "Set the structured filter that will be run against the user's saved recipes.",
        inputSchema: JSONSchema.object([
            "text": JSONSchema.string("Free keywords to match against recipe titles and ingredient names, e.g. a dish name. Null unless the user named a dish or keyword.", nullable: true),
            "include_ingredients": JSONSchema.array(of: JSONSchema.string("Lowercase singular canonical ingredient or category name."), description: "Ingredients the recipe must contain."),
            "exclude_ingredients": JSONSchema.array(of: JSONSchema.string("Lowercase singular canonical ingredient or category name, e.g. 'dairy', 'peanut', 'shellfish', 'chicken thigh'."), description: "Ingredients or categories the recipe must not contain."),
            "min_protein": JSONSchema.number("Minimum grams of protein per serving.", nullable: true),
            "max_protein": JSONSchema.number("Maximum grams of protein per serving.", nullable: true),
            "min_carbs": JSONSchema.number("Minimum grams of carbohydrate per serving.", nullable: true),
            "max_carbs": JSONSchema.number("Maximum grams of carbohydrate per serving.", nullable: true),
            "min_fat": JSONSchema.number("Minimum grams of fat per serving.", nullable: true),
            "max_fat": JSONSchema.number("Maximum grams of fat per serving.", nullable: true),
            "max_calories": JSONSchema.number("Maximum calories per serving.", nullable: true),
            "max_minutes": JSONSchema.integer("Maximum total prep plus cook time in minutes.", nullable: true),
            "tags": JSONSchema.array(of: JSONSchema.string("A tag such as 'weeknight' or 'comfort'."), description: "Tags the recipe must carry. Usually empty."),
            "meal_type": JSONSchema.string("One of breakfast, brunch, lunch, dinner, snack, dessert.", nullable: true, values: ["breakfast", "brunch", "lunch", "dinner", "snack", "dessert"]),
        ])
    )

    private static let system = """
    You convert a message into a structured search over the user's own saved recipes by calling set_search_query exactly once. You only produce the filter; you never choose recipes and never invent any.

    Interpretation defaults (per serving, grams): "high protein" → min_protein 30; "low carb" → max_carbs 20; "keto" → max_carbs 10; "low fat" → max_fat 15; "light" or "low calorie" → max_calories 400; "quick" → max_minutes 30. Explicit numbers override these.
    Diet words expand to exclusions: vegetarian → meat, fish, shellfish, gelatin; vegan → those plus dairy, egg, honey; pescatarian → meat; gluten-free → gluten; dairy-free → dairy; nut-free → nut.
    Exclusions and inclusions are lowercase, singular, canonical names ("peanut", not "peanuts"; "chicken thigh", not "the chicken thighs I have").
    If a current query is provided, the message refines it: return the complete updated query, keeping everything the user did not change, adding what they added, and dropping anything they asked to drop. "Reset" or "start over" returns an empty query.
    If the message is just a dish or keyword, put it in `text` and leave the rest empty.
    """

    func interpret(_ message: String, refining current: SearchQuery?) async throws -> SearchQuery {
        var prompt = ""
        if let current, !current.isEmpty, let data = try? JSONEncoder().encode(current) {
            prompt += "Current query (JSON):\n\(String(decoding: data, as: UTF8.self))\n\n"
        }
        prompt += "Message:\n\(message)"

        let p = try await client.invokeTool(Payload.self, system: Self.system, content: [.text(prompt)], tool: Self.tool, effort: .low, maxTokens: 2048)
        return SearchQuery(
            text: p.text?.isEmpty == false ? p.text : nil,
            includeIngredients: p.include_ingredients,
            excludeIngredients: p.exclude_ingredients,
            minProtein: p.min_protein,
            maxProtein: p.max_protein,
            minCarbs: p.min_carbs,
            maxCarbs: p.max_carbs,
            minFat: p.min_fat,
            maxFat: p.max_fat,
            maxCalories: p.max_calories,
            maxMinutes: p.max_minutes,
            tags: p.tags,
            mealType: p.meal_type)
    }
}
