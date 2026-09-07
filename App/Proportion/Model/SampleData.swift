import Foundation
import ProportionCore

/// Realistic recipes seeded when the app is launched with `-ui-testing`, so
/// screenshots and UI tests have something to show. Never used in a real
/// build's data store.
enum SampleData {
    static var recipes: [Recipe] {
        let taxonomy = IngredientTaxonomy.standard
        let parser = IngredientLineParser()
        func ingredients(_ lines: [String]) -> [Ingredient] {
            parser.parse(lines: lines).map(taxonomy.tagged)
        }
        let now = Date()

        return [
            Recipe(
                title: "Weeknight Chicken Thighs with Lemon & Herbs",
                sourceURL: URL(string: "https://example.com/lemon-chicken"),
                sourceAttribution: "example.com",
                baseServings: 4,
                ingredients: ingredients([
                    "8 boneless skinless chicken thighs",
                    "2 tbsp olive oil",
                    "3 cloves garlic, minced",
                    "1 lemon, juiced",
                    "1 tsp dried oregano",
                    "1/2 tsp chili flakes",
                    "salt to taste",
                    "black pepper to taste",
                    "1 bunch parsley, chopped",
                ]),
                steps: [
                    "Pat the chicken dry and season generously.",
                    "Sear skin-side down in olive oil over high heat until deeply golden, about 6 minutes.",
                    "Flip, add garlic, lemon juice and oregano, and finish in a 200°C oven for 15 minutes.",
                    "Rest 5 minutes, scatter with parsley, and serve.",
                ],
                prepMinutes: 10,
                cookMinutes: 25,
                totalMacros: Macros(protein: 176, fat: 92, carbs: 8),
                nutritionConfidence: .verified,
                tags: ["dinner", "weeknight"],
                createdAt: now.addingTimeInterval(-3600)),

            Recipe(
                title: "Greek Yogurt Protein Bowl",
                baseServings: 1,
                ingredients: ingredients([
                    "1 cup greek yogurt",
                    "1/2 cup blueberries",
                    "1 tbsp honey",
                    "2 tbsp almonds, sliced",
                    "a pinch of cinnamon",
                ]),
                steps: ["Spoon the yogurt into a bowl and top with everything else."],
                prepMinutes: 5,
                totalMacros: Macros(protein: 26, fat: 12, carbs: 38),
                nutritionConfidence: .verified,
                tags: ["breakfast", "quick"],
                createdAt: now.addingTimeInterval(-7200)),

            Recipe(
                title: "Baked Ziti",
                sourceAttribution: "Nonna",
                baseServings: 6,
                ingredients: ingredients([
                    "1 lb ziti",
                    "2 cups ricotta",
                    "2 cups mozzarella, shredded",
                    "1/2 cup parmesan, grated",
                    "1 egg",
                    "3 cups tomato sauce",
                    "1 tsp salt",
                    "1/4 tsp nutmeg",
                ]),
                steps: [
                    "Boil the ziti until just shy of al dente.",
                    "Mix ricotta, half the mozzarella, parmesan, egg and nutmeg.",
                    "Layer pasta, sauce and cheese mixture in a baking dish; top with remaining mozzarella.",
                    "Bake at 190°C for 30 minutes until bubbling.",
                ],
                prepMinutes: 20,
                cookMinutes: 40,
                totalMacros: Macros(protein: 168, fat: 138, carbs: 372),
                nutritionConfidence: .partiallyEstimated,
                tags: ["dinner", "comfort"],
                createdAt: now.addingTimeInterval(-86400)),

            Recipe(
                title: "Tofu Scramble",
                baseServings: 2,
                ingredients: ingredients([
                    "1 block firm tofu, crumbled",
                    "2 cups spinach",
                    "1 tbsp olive oil",
                    "1/2 tsp turmeric",
                    "1/2 tsp garlic powder",
                    "salt to taste",
                ]),
                steps: [
                    "Warm the oil, add tofu and spices, and fry until the edges crisp.",
                    "Wilt in the spinach and season.",
                ],
                prepMinutes: 5,
                cookMinutes: 10,
                totalMacros: Macros(protein: 36, fat: 30, carbs: 12),
                nutritionConfidence: .estimated,
                tags: ["breakfast", "vegan", "quick"],
                createdAt: now.addingTimeInterval(-172800)),

            Recipe(
                title: "Shrimp Stir-Fry",
                baseServings: 3,
                ingredients: ingredients([
                    "500 g shrimp, peeled",
                    "2 cups broccoli florets",
                    "3 tbsp soy sauce",
                    "1 tbsp sesame oil",
                    "2 cloves garlic",
                    "1 tsp cornstarch",
                    "2 cups cooked rice",
                ]),
                steps: [
                    "Toss shrimp with cornstarch and a splash of soy.",
                    "Stir-fry broccoli and garlic hard for 3 minutes, add shrimp for 2 more.",
                    "Finish with soy and sesame oil; serve over rice.",
                ],
                prepMinutes: 10,
                cookMinutes: 10,
                totalMacros: Macros(protein: 117, fat: 24, carbs: 138),
                nutritionConfidence: .verified,
                tags: ["dinner", "quick"],
                createdAt: now.addingTimeInterval(-259200)),
        ]
    }
}
