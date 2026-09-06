import XCTest
@testable import ProportionCore

final class ScalingEngineTests: XCTestCase {

    // A 4-serving fixture covering every kind of ingredient the engine has to handle.
    private func makeRecipe(macros: Macros? = Macros(protein: 100, fat: 40, carbs: 200)) -> Recipe {
        Recipe(
            title: "Test Chicken Bake",
            baseServings: 4,
            ingredients: [
                Ingredient(name: "all-purpose flour", quantity: Quantity(2, .cup), preparation: "sifted"),
                Ingredient(name: "chicken thighs", quantity: Quantity(500, .gram), grams: 500),
                Ingredient(name: "baking soda", quantity: Quantity(1, .teaspoon), isScalable: false),
                Ingredient(name: "cayenne", quantity: Quantity(Rational(1, 4), .teaspoon), isScalable: false),
                Ingredient(name: "salt", descriptor: "to taste"),
                Ingredient(name: "eggs", quantity: Quantity(2, .unitless)),
            ],
            steps: ["Mix.", "Bake."],
            totalMacros: macros
        )
    }

    private func quantity(_ scaled: ScaledRecipe, _ name: String) -> Quantity? {
        scaled.ingredients.first { $0.ingredient.name == name }?.quantity
    }

    private func note(_ scaled: ScaledRecipe, _ name: String) -> ScalingNote? {
        scaled.ingredients.first { $0.ingredient.name == name }?.note
    }

    // MARK: Basic scaling

    func testDoubling() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toServings: 8)

        XCTAssertEqual(scaled.factor, 2)
        XCTAssertEqual(scaled.servings, 8)
        XCTAssertEqual(quantity(scaled, "all-purpose flour"), Quantity(4, .cup))
        XCTAssertEqual(quantity(scaled, "chicken thighs"), Quantity(1000, .gram))
        XCTAssertEqual(quantity(scaled, "eggs"), Quantity(4, .unitless))
        XCTAssertEqual(quantity(scaled, "baking soda"), Quantity(2, .teaspoon))
    }

    func testHalving() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toServings: 2)

        XCTAssertEqual(scaled.factor, Rational(1, 2))
        XCTAssertEqual(quantity(scaled, "all-purpose flour"), Quantity(1, .cup))
        XCTAssertEqual(quantity(scaled, "chicken thighs"), Quantity(250, .gram))
        XCTAssertEqual(quantity(scaled, "eggs"), Quantity(1, .unitless))
        XCTAssertEqual(quantity(scaled, "cayenne"), Quantity(Rational(1, 8), .teaspoon))
    }

    func testAwkwardFactorStaysExact() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toServings: 7)
        XCTAssertEqual(scaled.factor, Rational(7, 4))
        XCTAssertEqual(quantity(scaled, "all-purpose flour"), Quantity(Rational(7, 2), .cup))
        XCTAssertEqual(quantity(scaled, "chicken thighs"), Quantity(875, .gram))
        XCTAssertEqual(quantity(scaled, "eggs"), Quantity(Rational(7, 2), .unitless))
    }

    // MARK: Pass-through and notes

    func testNonNumericQuantitiesPassThroughUnchanged() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toServings: 12)
        let salt = try XCTUnwrap(scaled.ingredients.first { $0.ingredient.name == "salt" })
        XCTAssertNil(salt.quantity)
        XCTAssertEqual(salt.ingredient.descriptor, "to taste")
        XCTAssertNil(salt.note)
    }

    func testNonScalableIngredientsAreScaledButFlagged() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toServings: 8)
        XCTAssertEqual(note(scaled, "baking soda"), .adjustByTaste)
        XCTAssertEqual(note(scaled, "cayenne"), .adjustByTaste)
        XCTAssertNil(note(scaled, "all-purpose flour"))
        XCTAssertEqual(ScalingNote.adjustByTaste.message, "Seasoning may need adjusting by taste")
    }

    func testNoNotesAtBaseServings() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toServings: 4)
        XCTAssertTrue(scaled.ingredients.allSatisfy { $0.note == nil })
    }

    // MARK: Range

    func testServingRangeIsEnforced() {
        let recipe = makeRecipe()
        XCTAssertThrowsError(try ScalingEngine.scale(recipe, toServings: 0)) { error in
            XCTAssertEqual(error as? ScalingError, .servingsOutOfRange(0))
        }
        XCTAssertThrowsError(try ScalingEngine.scale(recipe, toServings: 51)) { error in
            XCTAssertEqual(error as? ScalingError, .servingsOutOfRange(51))
        }
        XCTAssertNoThrow(try ScalingEngine.scale(recipe, toServings: 1))
        XCTAssertNoThrow(try ScalingEngine.scale(recipe, toServings: 50))
    }

    // MARK: Non-destructive

    func testScalingNeverMutatesTheBaseRecipe() throws {
        let recipe = makeRecipe()
        let snapshot = recipe
        let scaled = try ScalingEngine.scale(recipe, toServings: 50)
        XCTAssertEqual(recipe, snapshot)
        XCTAssertEqual(scaled.base, snapshot)
        XCTAssertEqual(recipe.ingredients[0].quantity, Quantity(2, .cup))
    }

    func testIdentityScalingReproducesBaseExactly() throws {
        let recipe = makeRecipe()
        let scaled = try ScalingEngine.scale(recipe, toServings: recipe.baseServings)
        XCTAssertEqual(scaled.factor, .one)
        XCTAssertEqual(scaled.ingredients.map(\.quantity), recipe.ingredients.map(\.quantity))
    }

    // MARK: Drift

    /// Simulates a user hammering the serving stepper up and down. Because
    /// every step is computed from the base recipe, returning to the base
    /// count must reproduce it bit-for-bit.
    func testRepeatedScalingDoesNotDrift() throws {
        let recipe = makeRecipe()
        var targets: [Int] = []
        targets += Array(5...50)
        targets += Array((1...49).reversed())
        targets += [3, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 4]

        var last: ScaledRecipe?
        for target in targets {
            last = try ScalingEngine.scale(recipe, toServings: target)
        }
        let final = try XCTUnwrap(last)
        XCTAssertEqual(final.servings, 4)
        XCTAssertEqual(final.ingredients.map(\.quantity), recipe.ingredients.map(\.quantity))
    }

    func testScalingUpThenDownReturnsExactBase() throws {
        // Even via an intermediate awkward factor, the maths is exact.
        let recipe = makeRecipe()
        let up = try ScalingEngine.scale(recipe, toServings: 7)
        let flourAt7 = try XCTUnwrap(quantity(up, "all-purpose flour"))
        let backDown = flourAt7.scaled(by: Rational(4, 7))
        XCTAssertEqual(backDown, Quantity(2, .cup))
    }

    // MARK: Macros

    func testPerServingMacrosAreInvariantUnderScaling() throws {
        let recipe = makeRecipe()
        let base = try XCTUnwrap(recipe.perServingMacros)
        XCTAssertEqual(base.protein, 25, accuracy: 1e-9)

        for target in [1, 2, 8, 13, 50] {
            let scaled = try ScalingEngine.scale(recipe, toServings: target)
            let per = try XCTUnwrap(scaled.perServingMacros)
            XCTAssertEqual(per.protein, 25, accuracy: 1e-9, "at \(target) servings")
            XCTAssertEqual(per.fat, 10, accuracy: 1e-9)
            XCTAssertEqual(per.carbs, 50, accuracy: 1e-9)
        }
    }

    func testTotalMacrosScaleWithFactor() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toServings: 8)
        let total = try XCTUnwrap(scaled.totalMacros)
        XCTAssertEqual(total.protein, 200, accuracy: 1e-9)
        XCTAssertEqual(total.fat, 80, accuracy: 1e-9)
        XCTAssertEqual(total.carbs, 400, accuracy: 1e-9)
    }

    func testCaloriesUseAtwaterFactors() {
        let m = Macros(protein: 100, fat: 40, carbs: 200)
        let expected: Double = (100.0 * 4.0) + (200.0 * 4.0) + (40.0 * 9.0)
        XCTAssertEqual(m.calories, expected, accuracy: 1e-9)
    }

    func testMissingMacrosPropagateAsNil() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(macros: nil), toServings: 8)
        XCTAssertNil(scaled.totalMacros)
        XCTAssertNil(scaled.perServingMacros)
    }

    // MARK: Protein target

    func testScalingToProteinTarget() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toTotalProtein: 150)
        XCTAssertEqual(scaled.factor, Rational(3, 2))
        XCTAssertEqual(scaled.servings, 6)
        XCTAssertEqual(quantity(scaled, "all-purpose flour"), Quantity(3, .cup))
        XCTAssertEqual(try XCTUnwrap(scaled.totalMacros).protein, 150, accuracy: 1e-9)
    }

    func testProteinTargetCanYieldFractionalServings() throws {
        let scaled = try ScalingEngine.scale(makeRecipe(), toTotalProtein: 60)
        XCTAssertEqual(scaled.factor, Rational(3, 5))
        XCTAssertEqual(scaled.servings, Rational(12, 5))
    }

    func testProteinTargetOutsideServingRangeThrows() {
        XCTAssertThrowsError(try ScalingEngine.scale(makeRecipe(), toTotalProtein: 2000)) { error in
            XCTAssertEqual(error as? ScalingError, .servingsOutOfRange(80))
        }
        XCTAssertThrowsError(try ScalingEngine.scale(makeRecipe(), toTotalProtein: 10)) { error in
            XCTAssertEqual(error as? ScalingError, .servingsOutOfRange(0))
        }
    }

    func testProteinTargetRequiresNutritionData() {
        XCTAssertThrowsError(try ScalingEngine.scale(makeRecipe(macros: nil), toTotalProtein: 100)) { error in
            XCTAssertEqual(error as? ScalingError, .noNutritionData)
        }
    }

    func testProteinTargetMustBePositive() {
        XCTAssertThrowsError(try ScalingEngine.scale(makeRecipe(), toTotalProtein: 0)) { error in
            XCTAssertEqual(error as? ScalingError, .invalidProteinTarget)
        }
    }

    // MARK: Formatter integration

    func testScaledQuantitiesRenderThroughFormatter() throws {
        let f = QuantityFormatter()
        let doubled = try ScalingEngine.scale(makeRecipe(), toServings: 8)
        let lines = doubled.ingredients.map(f.line(for:))
        XCTAssertEqual(lines, [
            "4 cups all-purpose flour, sifted",
            "1 kg chicken thighs",
            "2 tsp baking soda",
            "½ tsp cayenne",
            "salt, to taste",
            "4 eggs",
        ])
    }
}
