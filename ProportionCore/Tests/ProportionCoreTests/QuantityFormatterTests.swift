import XCTest
@testable import ProportionCore

final class QuantityFormatterTests: XCTestCase {

    private let f = QuantityFormatter()

    private func s(_ amount: Rational, _ unit: MeasurementUnit) -> String {
        f.string(for: Quantity(amount, unit))
    }

    // MARK: Promotion — the thresholds named in the spec

    func testPromotesAtWholeUnitThresholds() {
        XCTAssertEqual(s(3, .teaspoon), "1 tbsp")
        XCTAssertEqual(s(16, .tablespoon), "1 cup")
        XCTAssertEqual(s(1000, .gram), "1 kg")
        XCTAssertEqual(s(1000, .milliliter), "1 L")
        XCTAssertEqual(s(16, .ounce), "1 lb")
    }

    func testPromotesToQuarterCup() {
        XCTAssertEqual(s(4, .tablespoon), "¼ cup")
        XCTAssertEqual(s(12, .teaspoon), "¼ cup")
    }

    func testDoesNotPromoteBelowThreshold() {
        XCTAssertEqual(s(2, .teaspoon), "2 tsp")
        XCTAssertEqual(s(3, .tablespoon), "3 tbsp")
        XCTAssertEqual(s(999, .gram), "1 kg", "999 g rounds to 1000 g first, then promotes")
        XCTAssertEqual(s(950, .gram), "950 g")
    }

    // MARK: Demotion

    func testDemotesSmallAmountsToSmallerUnits() {
        XCTAssertEqual(s(Rational(1, 8), .cup), "2 tbsp")
        XCTAssertEqual(s(Rational(1, 2), .tablespoon), "1 ½ tsp")
        XCTAssertEqual(s(Rational(1, 2), .kilogram), "500 g")
        XCTAssertEqual(s(Rational(1, 2), .liter), "500 ml")
        XCTAssertEqual(s(Rational(1, 2), .pound), "8 oz")
    }

    func testFluidOuncesRenderAsCupsOrSpoons() {
        XCTAssertEqual(s(8, .fluidOunce), "1 cup")
        XCTAssertEqual(s(1, .fluidOunce), "2 tbsp")
    }

    // MARK: Clean fractions survive

    func testPreservesCleanFractions() {
        XCTAssertEqual(s(Rational(1, 3), .cup), "⅓ cup")
        XCTAssertEqual(s(Rational(2, 3), .cup), "⅔ cup")
        XCTAssertEqual(s(Rational(3, 2), .cup), "1 ½ cups")
        XCTAssertEqual(s(Rational(3, 4), .teaspoon), "¾ tsp")
        XCTAssertEqual(s(Rational(5, 6), .cup), "⅚ cup")
    }

    // MARK: Rounding

    func testRoundsAwkwardFractionsToGrid() {
        XCTAssertEqual(s(Rational(5, 12), .cup), "⅜ cup")
        XCTAssertEqual(s(Rational(29, 10), .teaspoon), "1 tbsp", "2.9 tsp rounds to 3 tsp, then promotes")
        XCTAssertEqual(s(Rational(11, 3), .tablespoon), "3 ¾ tbsp")
    }

    func testRoundsMetricMassByMagnitude() {
        XCTAssertEqual(s(133, .gram), "125 g", "25 g steps from 100 g up")
        XCTAssertEqual(s(83, .gram), "85 g", "5 g steps below 100 g")
        XCTAssertEqual(s(47, .gram), "45 g")
        XCTAssertEqual(s(240, .gram), "250 g")
        XCTAssertEqual(s(112, .gram), "100 g")
        XCTAssertEqual(s(1234, .gram), "1.225 kg")
        XCTAssertEqual(s(2500, .gram), "2.5 kg")
        XCTAssertEqual(s(Rational(5, 2), .kilogram), "2.5 kg")
    }

    func testRoundsMetricVolumeByMagnitude() {
        XCTAssertEqual(s(237, .milliliter), "240 ml")
        XCTAssertEqual(s(48, .milliliter), "50 ml")
    }

    func testTinyAmountsNeverRoundToZero() {
        XCTAssertEqual(s(Rational(1, 16), .teaspoon), "⅛ tsp")
        XCTAssertEqual(s(Rational(1, 64), .teaspoon), "⅛ tsp")
        XCTAssertEqual(s(2, .gram), "2 g")
        XCTAssertEqual(s(Rational(1, 3), .gram), "1 g")
    }

    // MARK: Counts

    func testCountUnitsNeverConvert() {
        XCTAssertEqual(s(3, .clove), "3 cloves")
        XCTAssertEqual(s(1, .clove), "1 clove")
        XCTAssertEqual(s(Rational(3, 2), .piece), "1 ½ pieces")
        XCTAssertEqual(s(2, .can), "2 cans")
        XCTAssertEqual(s(2, .bunch), "2 bunches")
    }

    func testUnitlessRendersBareNumber() {
        XCTAssertEqual(s(2, .unitless), "2")
        XCTAssertEqual(s(Rational(1, 2), .unitless), "½")
        XCTAssertEqual(s(Rational(5, 2), .unitless), "2 ½")
    }

    func testCountsRoundToHalves() {
        XCTAssertEqual(s(Rational(7, 3), .piece), "2 ½ pieces")
    }

    // MARK: Pluralisation

    func testPluralisesOnlyAboveOne() {
        XCTAssertEqual(s(1, .cup), "1 cup")
        XCTAssertEqual(s(Rational(1, 2), .cup), "½ cup")
        XCTAssertEqual(s(2, .cup), "2 cups")
        XCTAssertEqual(s(Rational(9, 8), .cup), "1 ⅛ cups")
    }

    // MARK: Cross-system display

    func testMetricPreference() {
        let metric = QuantityFormatter(unitSystem: .metric)
        XCTAssertEqual(metric.string(for: Quantity(1, .cup)), "240 ml")
        XCTAssertEqual(metric.string(for: Quantity(1, .pound)), "450 g")
        XCTAssertEqual(metric.string(for: Quantity(1, .teaspoon)), "5 ml")
        XCTAssertEqual(metric.string(for: Quantity(500, .gram)), "500 g", "already metric: untouched")
    }

    func testUSPreference() {
        let us = QuantityFormatter(unitSystem: .us)
        XCTAssertEqual(us.string(for: Quantity(250, .gram)), "8 ¾ oz")
        XCTAssertEqual(us.string(for: Quantity(500, .milliliter)), "2 ⅛ cups")
        XCTAssertEqual(us.string(for: Quantity(1, .cup)), "1 cup", "already US: untouched")
    }

    func testAsAuthoredLeavesFamiliesAlone() {
        XCTAssertEqual(s(1, .cup), "1 cup")
        XCTAssertEqual(s(500, .gram), "500 g")
    }

    // MARK: Ingredient lines

    func testIngredientLineWithQuantityAndPreparation() {
        let ingredient = Ingredient(name: "all-purpose flour", quantity: Quantity(2, .cup), preparation: "sifted")
        let scaled = ScaledIngredient(ingredient: ingredient, quantity: ingredient.quantity, note: nil)
        XCTAssertEqual(f.line(for: scaled), "2 cups all-purpose flour, sifted")
    }

    func testIngredientLineWithDescriptor() {
        let ingredient = Ingredient(name: "salt", descriptor: "to taste")
        let scaled = ScaledIngredient(ingredient: ingredient, quantity: nil, note: nil)
        XCTAssertEqual(f.line(for: scaled), "salt, to taste")
    }

    func testIngredientLineUnitless() {
        let ingredient = Ingredient(name: "eggs", quantity: Quantity(2, .unitless))
        let scaled = ScaledIngredient(ingredient: ingredient, quantity: ingredient.quantity, note: nil)
        XCTAssertEqual(f.line(for: scaled), "2 eggs")
    }

    // MARK: normalized() is exact, not stringly

    func testNormalizedReturnsExactQuantity() {
        XCTAssertEqual(f.normalized(Quantity(3, .teaspoon)), Quantity(1, .tablespoon))
        XCTAssertEqual(f.normalized(Quantity(Rational(5, 12), .cup)), Quantity(Rational(3, 8), .cup))
        XCTAssertEqual(f.normalized(Quantity(1234, .gram)), Quantity(Rational(49, 40), .kilogram))
    }
}
