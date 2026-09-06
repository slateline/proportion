import XCTest
@testable import ProportionCore

final class IngredientLineParserTests: XCTestCase {

    private let p = IngredientLineParser()

    func testSimpleLine() {
        let i = p.parse("2 cups all-purpose flour, sifted")
        XCTAssertEqual(i.quantity, Quantity(2, .cup))
        XCTAssertEqual(i.name, "all-purpose flour")
        XCTAssertEqual(i.preparation, "sifted")
        XCTAssertNil(i.descriptor)
        XCTAssertTrue(i.isScalable)
    }

    func testFractions() {
        XCTAssertEqual(p.parse("1/2 tsp salt").quantity, Quantity(Rational(1, 2), .teaspoon))
        XCTAssertEqual(p.parse("1 1/2 cups milk").quantity, Quantity(Rational(3, 2), .cup))
        XCTAssertEqual(p.parse("½ cup sugar").quantity, Quantity(Rational(1, 2), .cup))
        XCTAssertEqual(p.parse("1½ cups milk").quantity, Quantity(Rational(3, 2), .cup))
        XCTAssertEqual(p.parse("1 ½ cups milk").quantity, Quantity(Rational(3, 2), .cup))
    }

    func testDecimals() {
        XCTAssertEqual(p.parse("1.5 kg potatoes").quantity, Quantity(Rational(3, 2), .kilogram))
        XCTAssertEqual(p.parse("0.25 cup oil").quantity, Quantity(Rational(1, 4), .cup))
    }

    func testGluedUnits() {
        let i = p.parse("500g chicken thighs")
        XCTAssertEqual(i.quantity, Quantity(500, .gram))
        XCTAssertEqual(i.name, "chicken thighs")
        XCTAssertEqual(p.parse("2tbsp olive oil").quantity, Quantity(2, .tablespoon))
        XCTAssertEqual(p.parse("250ml cream").quantity, Quantity(250, .milliliter))
    }

    func testUnitAliases() {
        XCTAssertEqual(p.parse("3 tablespoons butter").quantity?.unit, .tablespoon)
        XCTAssertEqual(p.parse("2 Tbsp. butter").quantity?.unit, .tablespoon)
        XCTAssertEqual(p.parse("1 T butter").quantity?.unit, .tablespoon)
        XCTAssertEqual(p.parse("1 t salt").quantity?.unit, .teaspoon)
        XCTAssertEqual(p.parse("8 fl oz milk").quantity, Quantity(8, .fluidOunce))
        XCTAssertEqual(p.parse("1 lb ground beef").quantity, Quantity(1, .pound))
        XCTAssertEqual(p.parse("2 lbs ground beef").quantity, Quantity(2, .pound))
        XCTAssertEqual(p.parse("1 litre water").quantity, Quantity(1, .liter))
    }

    func testCountUnits() {
        let garlic = p.parse("3 cloves garlic, minced")
        XCTAssertEqual(garlic.quantity, Quantity(3, .clove))
        XCTAssertEqual(garlic.name, "garlic")
        XCTAssertEqual(garlic.preparation, "minced")

        let eggs = p.parse("3 large eggs")
        XCTAssertEqual(eggs.quantity, Quantity(3, .unitless))
        XCTAssertEqual(eggs.name, "large eggs")
    }

    func testOfIsDropped() {
        let i = p.parse("2 cups of flour")
        XCTAssertEqual(i.quantity, Quantity(2, .cup))
        XCTAssertEqual(i.name, "flour")
    }

    func testRangesTakeTheLowerBound() {
        XCTAssertEqual(p.parse("2-3 cloves garlic").quantity, Quantity(2, .clove))
        XCTAssertEqual(p.parse("2 - 3 cloves garlic").quantity, Quantity(2, .clove))
        XCTAssertEqual(p.parse("2 to 3 cloves garlic").name, "garlic")
    }

    func testNumberWords() {
        XCTAssertEqual(p.parse("one onion, diced").quantity, Quantity(1, .unitless))
        XCTAssertEqual(p.parse("a can of chickpeas").quantity, Quantity(1, .can))
        XCTAssertEqual(p.parse("half a lemon").quantity, Quantity(Rational(1, 2), .unitless))
    }

    func testParentheticalsBecomeNotes() {
        let i = p.parse("1 (14 oz) can chickpeas, drained and rinsed")
        XCTAssertEqual(i.quantity, Quantity(1, .can))
        XCTAssertEqual(i.name, "chickpeas")
        XCTAssertEqual(i.preparation, "drained and rinsed, 14 oz")
    }

    func testDescriptors() {
        let salt = p.parse("salt to taste")
        XCTAssertNil(salt.quantity)
        XCTAssertEqual(salt.name, "salt")
        XCTAssertEqual(salt.descriptor, "to taste")

        let salt2 = p.parse("Salt, to taste")
        XCTAssertEqual(salt2.name, "Salt")
        XCTAssertEqual(salt2.descriptor, "to taste")

        let nutmeg = p.parse("a pinch of nutmeg")
        XCTAssertNil(nutmeg.quantity)
        XCTAssertEqual(nutmeg.name, "nutmeg")
        XCTAssertEqual(nutmeg.descriptor, "a pinch")

        let garnish = p.parse("chopped parsley, for garnish")
        XCTAssertEqual(garnish.name, "chopped parsley")
        XCTAssertEqual(garnish.descriptor, "for garnish")
    }

    func testUnparseableLinesKeepTheirText() {
        let i = p.parse("juice of 1 lemon")
        XCTAssertNil(i.quantity)
        XCTAssertEqual(i.name, "juice of 1 lemon")
    }

    func testNonLinearItemsAreFlagged() {
        XCTAssertFalse(p.parse("1 tsp baking soda").isScalable)
        XCTAssertFalse(p.parse("1/4 tsp cayenne pepper").isScalable)
        XCTAssertFalse(p.parse("salt to taste").isScalable)
        XCTAssertTrue(p.parse("2 cups flour").isScalable)
        XCTAssertTrue(p.parse("500 g chicken").isScalable)
    }

    func testBatchParsingSkipsBlankLines() {
        let items = p.parse(lines: ["2 cups flour", "", "   ", "1 tsp salt"])
        XCTAssertEqual(items.map(\.name), ["flour", "salt"])
    }

    func testRoundTripsThroughFormatter() {
        let f = QuantityFormatter()
        let i = p.parse("1 1/2 cups all-purpose flour, sifted")
        let scaled = ScaledIngredient(ingredient: i, quantity: i.quantity, note: nil)
        XCTAssertEqual(f.line(for: scaled), "1 ½ cups all-purpose flour, sifted")
    }
}
