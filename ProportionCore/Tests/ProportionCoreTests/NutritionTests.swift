import XCTest
@testable import ProportionCore

final class GramEstimatorTests: XCTestCase {

    private let g = GramEstimator()

    func testMassUnitsAreExact() {
        XCTAssertEqual(g.grams(for: Ingredient(name: "chicken", quantity: Quantity(500, .gram))), 500)
        XCTAssertEqual(g.grams(for: Ingredient(name: "chicken", quantity: Quantity(Rational(1, 2), .kilogram))), 500)
        XCTAssertEqual(try XCTUnwrap(g.grams(for: Ingredient(name: "beef", quantity: Quantity(1, .pound)))), 453.59, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(g.grams(for: Ingredient(name: "beef", quantity: Quantity(4, .ounce)))), 113.4, accuracy: 0.01)
    }

    func testVolumeUsesDensity() {
        XCTAssertEqual(g.grams(for: Ingredient(name: "all-purpose flour", quantity: Quantity(2, .cup))), 250)
        XCTAssertEqual(try XCTUnwrap(g.grams(for: Ingredient(name: "butter", quantity: Quantity(1, .tablespoon)))), 227.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(g.grams(for: Ingredient(name: "milk", quantity: Quantity(250, .milliliter)))), 245 * 250 / 236.5882365, accuracy: 1e-6)
    }

    func testVolumeFallsBackUpTheTaxonomy() {
        // "gruyere" has no density of its own; "hard cheese" doesn't either; "cheese" does.
        XCTAssertEqual(g.grams(for: Ingredient(name: "gruyere", quantity: Quantity(1, .cup))), 113)
        XCTAssertEqual(g.grams(for: Ingredient(name: "bread flour", quantity: Quantity(1, .cup))), 127, "own entry wins over the parent")
    }

    func testUnknownVolumeIsUnresolved() {
        XCTAssertNil(g.grams(for: Ingredient(name: "dragonfruit", quantity: Quantity(1, .cup))))
    }

    func testCounts() {
        XCTAssertEqual(g.grams(for: Ingredient(name: "eggs", quantity: Quantity(2, .unitless))), 100)
        XCTAssertEqual(g.grams(for: Ingredient(name: "large eggs", quantity: Quantity(3, .unitless))), 150)
        XCTAssertEqual(g.grams(for: Ingredient(name: "garlic", quantity: Quantity(3, .clove))), 9)
        XCTAssertEqual(g.grams(for: Ingredient(name: "chickpeas", quantity: Quantity(1, .can))), 400)
        XCTAssertEqual(g.grams(for: Ingredient(name: "butter", quantity: Quantity(1, .stick))), 113)
        XCTAssertEqual(g.grams(for: Ingredient(name: "bread", quantity: Quantity(2, .slice))), 60)
        XCTAssertEqual(g.grams(for: Ingredient(name: "parsley", quantity: Quantity(1, .bunch))), 60)
        XCTAssertNil(g.grams(for: Ingredient(name: "dragonfruit", quantity: Quantity(2, .unitless))))
    }

    func testExplicitGramsWin() {
        XCTAssertEqual(g.grams(for: Ingredient(name: "flour", quantity: Quantity(1, .cup), grams: 999)), 999)
    }

    func testDescriptorOnlyIsNil() {
        XCTAssertNil(g.grams(for: Ingredient(name: "salt", descriptor: "to taste")))
    }
}

final class NutritionCalculatorTests: XCTestCase {

    private let source = InMemoryNutrientSource([
        "chicken thigh": FoodNutrients(description: "Chicken, thigh, raw", sourceID: "1", per100g: Macros(protein: 17, fat: 10, carbs: 0)),
        "all-purpose flour": FoodNutrients(description: "Wheat flour, white", sourceID: "2", per100g: Macros(protein: 10, fat: 1, carbs: 76)),
        "egg": FoodNutrients(description: "Egg, whole, raw", sourceID: "3", per100g: Macros(protein: 12.6, fat: 9.5, carbs: 0.7)),
    ])

    private struct FixedEstimator: NutritionEstimator {
        let macros: Macros
        func estimate(ingredient: Ingredient, grams: Double?) async throws -> Macros? { macros }
    }

    private func recipe() -> Recipe {
        Recipe(title: "Bake", baseServings: 4, ingredients: [
            Ingredient(name: "chicken thighs", quantity: Quantity(500, .gram)),
            Ingredient(name: "all-purpose flour", quantity: Quantity(2, .cup)),
            Ingredient(name: "eggs", quantity: Quantity(2, .unitless)),
            Ingredient(name: "mystery spice blend", quantity: Quantity(1, .teaspoon)),
            Ingredient(name: "salt", descriptor: "to taste"),
        ])
    }

    func testVerifiedItemsSumCorrectly() async {
        let calc = NutritionCalculator(source: source)
        let report = await calc.report(for: recipe())

        XCTAssertEqual(report.items.count, 5)
        XCTAssertEqual(report.items[0].status, .verified)
        XCTAssertEqual(report.items[0].grams, 500)
        XCTAssertEqual(try XCTUnwrap(report.items[0].macros).protein, 85, accuracy: 1e-9)
        XCTAssertEqual(report.items[0].matchedFood, "Chicken, thigh, raw")

        XCTAssertEqual(report.items[1].status, .verified)
        XCTAssertEqual(try XCTUnwrap(report.items[1].macros).carbs, 190, accuracy: 1e-9)

        XCTAssertEqual(report.items[2].status, .verified, "'eggs' resolves to 'egg' through the taxonomy")
        XCTAssertEqual(try XCTUnwrap(report.items[2].macros).protein, 12.6, accuracy: 1e-9)

        XCTAssertEqual(report.total.protein, 85 + 25 + 12.6, accuracy: 1e-9)
    }

    func testUnresolvedAndNegligibleItems() async {
        let calc = NutritionCalculator(source: source)
        let report = await calc.report(for: recipe())

        let spice = report.items[3]
        XCTAssertEqual(spice.status, .unresolved)
        XCTAssertNil(spice.macros)
        XCTAssertFalse(spice.isNegligible)

        let salt = report.items[4]
        XCTAssertEqual(salt.status, .unresolved)
        XCTAssertTrue(salt.isNegligible)

        XCTAssertEqual(report.unresolved.map(\.name), ["mystery spice blend"])
    }

    func testConfidenceStates() async {
        // One unresolved priced item → partially estimated.
        let partial = await NutritionCalculator(source: source).report(for: recipe())
        XCTAssertEqual(partial.confidence, .partiallyEstimated)

        // Estimator fills the gap → still partially estimated (some verified, some not).
        let withEstimator = NutritionCalculator(source: source, estimator: FixedEstimator(macros: Macros(protein: 0, fat: 0, carbs: 1)))
        let mixed = await withEstimator.report(for: recipe())
        XCTAssertEqual(mixed.items[3].status, .estimated)
        XCTAssertEqual(mixed.confidence, .partiallyEstimated)
        XCTAssertEqual(mixed.items[4].status, .unresolved, "negligible items are never sent to the estimator")

        // Everything verified.
        let allKnown = Recipe(title: "Simple", baseServings: 1, ingredients: [
            Ingredient(name: "egg", quantity: Quantity(1, .unitless)),
            Ingredient(name: "salt", descriptor: "to taste"),
        ])
        let verified = await NutritionCalculator(source: source).report(for: allKnown)
        XCTAssertEqual(verified.confidence, .verified)

        // Nothing verifiable, estimator only.
        let unknownRecipe = Recipe(title: "Odd", baseServings: 1, ingredients: [
            Ingredient(name: "dragonfruit", quantity: Quantity(200, .gram)),
        ])
        let estimated = await withEstimator.report(for: unknownRecipe)
        XCTAssertEqual(estimated.confidence, .estimated)

        // Nothing at all.
        let nothing = await NutritionCalculator(source: source).report(for: unknownRecipe)
        XCTAssertEqual(nothing.confidence, .unknown)
    }

    func testApplyWritesTotalsOntoRecipe() async {
        let calc = NutritionCalculator(source: source)
        let base = recipe()
        let report = await calc.report(for: base)
        let updated = calc.apply(report, to: base)
        XCTAssertEqual(updated.nutritionConfidence, .partiallyEstimated)
        XCTAssertEqual(try XCTUnwrap(updated.totalMacros).protein, report.total.protein, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(updated.perServingMacros).protein, report.total.protein / 4, accuracy: 1e-9)
        XCTAssertEqual(base.totalMacros, nil, "apply is non-destructive")
    }
}

final class USDAParsingTests: XCTestCase {

    func testParsesNutrientIDs() throws {
        let json = """
        {"foods":[
          {"fdcId":171077,"description":"Chicken, thigh, raw",
           "foodNutrients":[{"nutrientId":1003,"value":17.3},{"nutrientId":1004,"value":10.1},{"nutrientId":1005,"value":0},{"nutrientId":1008,"value":170}]}
        ]}
        """
        let food = try XCTUnwrap(USDAFoodDataClient.parse(Data(json.utf8)))
        XCTAssertEqual(food.description, "Chicken, thigh, raw")
        XCTAssertEqual(food.sourceID, "171077")
        XCTAssertEqual(food.per100g, Macros(protein: 17.3, fat: 10.1, carbs: 0))
    }

    func testParsesNutrientNumbersAndSkipsFoodsWithoutMacros() throws {
        let json = """
        {"foods":[
          {"fdcId":1,"description":"Useless","foodNutrients":[{"nutrientNumber":"208","value":100}]},
          {"fdcId":2,"description":"Flour","foodNutrients":[{"nutrientNumber":"203","value":10},{"nutrientNumber":"205","value":76}]}
        ]}
        """
        let food = try XCTUnwrap(USDAFoodDataClient.parse(Data(json.utf8)))
        XCTAssertEqual(food.description, "Flour")
        XCTAssertEqual(food.per100g, Macros(protein: 10, fat: 0, carbs: 76))
    }

    func testEmptyResults() throws {
        XCTAssertNil(try USDAFoodDataClient.parse(Data(#"{"foods":[]}"#.utf8)))
    }
}
