import XCTest
@testable import ProportionCore

final class PlainTextRecipeParserTests: XCTestCase {

    private let p = PlainTextRecipeParser()

    func testSectionedRecipe() throws {
        let text = """
        Weeknight Chicken Bake
        Serves 4
        Prep time: 15 min
        Cook time: 1 hr 10 min

        Ingredients
        - 500g chicken thighs
        - 2 cups all-purpose flour, sifted
        - 1 tsp baking soda
        - salt to taste

        Method
        1. Preheat the oven to 200C.
        2. Mix everything.
        Step 3: Bake for 70 minutes.

        Notes
        Freezes well.
        """
        let draft = try XCTUnwrap(p.parse(text))
        XCTAssertEqual(draft.title, "Weeknight Chicken Bake")
        XCTAssertEqual(draft.servings, 4)
        XCTAssertEqual(draft.prepMinutes, 15)
        XCTAssertEqual(draft.cookMinutes, 70)
        XCTAssertEqual(draft.ingredientLines, ["500g chicken thighs", "2 cups all-purpose flour, sifted", "1 tsp baking soda", "salt to taste"])
        XCTAssertEqual(draft.steps, ["Preheat the oven to 200C.", "Mix everything.", "Bake for 70 minutes."])
        XCTAssertEqual(draft.source, .pastedText)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(draft.parseConfidence), 0.6)
        XCTAssertTrue(draft.warnings.isEmpty)
    }

    func testUnsectionedRecipeIsClassifiedLineByLine() throws {
        let text = """
        Quick Pancakes
        1 cup flour
        1 egg
        1 cup milk
        2 tbsp sugar
        Whisk the wet ingredients together, then fold in the flour.
        Cook on a hot griddle until bubbles form, then flip.
        """
        let draft = try XCTUnwrap(p.parse(text))
        XCTAssertEqual(draft.title, "Quick Pancakes")
        XCTAssertEqual(draft.ingredientLines.count, 4)
        XCTAssertEqual(draft.steps.count, 2)
        XCTAssertNil(draft.servings)
    }

    func testNonRecipeTextReturnsNil() {
        XCTAssertNil(p.parse("Just a paragraph about my weekend. It was nice. We went hiking."))
        XCTAssertNil(p.parse(""))
    }

    func testLowConfidenceWhenFewQuantities() throws {
        let draft = try XCTUnwrap(p.parse("Stuff\nsalt to taste\npepper to taste\nMix."))
        XCTAssertLessThan(try XCTUnwrap(draft.parseConfidence), 0.6)
        XCTAssertFalse(draft.warnings.isEmpty, "no real steps → warning")
    }

    func testMetadataHelpers() {
        XCTAssertEqual(PlainTextRecipeParser.servings(in: "Serves 6"), 6)
        XCTAssertEqual(PlainTextRecipeParser.servings(in: "Yield: 12 muffins"), 12)
        XCTAssertEqual(PlainTextRecipeParser.servings(in: "Makes 4 servings"), 4)
        XCTAssertNil(PlainTextRecipeParser.servings(in: "2 cups flour"))
        XCTAssertEqual(PlainTextRecipeParser.time(in: "Cook Time: 1 hour 30 minutes")?.1, 90)
        XCTAssertEqual(PlainTextRecipeParser.time(in: "prep time 10 mins")?.0, "prep")
        XCTAssertNil(PlainTextRecipeParser.time(in: "10 minutes later, stir"))
    }

    func testBulletsAndNumberingAreStripped() {
        XCTAssertEqual(PlainTextRecipeParser.cleanLine("  • 2 cups   flour "), "2 cups flour")
        XCTAssertEqual(PlainTextRecipeParser.cleanLine("▢ 1 egg"), "1 egg")
        XCTAssertEqual(PlainTextRecipeParser.stripStepNumbering("3) Bake it."), "Bake it.")
        XCTAssertEqual(PlainTextRecipeParser.stripStepNumbering("Step 2: Stir"), "Stir")
    }

    func testDraftMakesRecipe() throws {
        let draft = try XCTUnwrap(p.parse("Toast\n2 slices bread\n1 tbsp butter\nToast the bread and butter it generously."))
        let (recipe, _) = draft.makeRecipe()
        XCTAssertEqual(recipe.ingredients[0].quantity, Quantity(2, .slice))
        XCTAssertEqual(recipe.ingredients[1].quantity, Quantity(1, .tablespoon))
        XCTAssertTrue(recipe.ingredients[1].categoryTags.contains("dairy"))
    }
}

final class HTMLTextExtractorTests: XCTestCase {

    private let x = HTMLTextExtractor()

    func testStripsChromeAndKeepsContentLines() {
        let html = """
        <html><head><title>Best &amp; Easiest Pancakes | Site</title><style>p{color:red}</style></head>
        <body><nav><a href="/">Home</a></nav>
        <script>track()</script>
        <h1>Best &amp; Easiest Pancakes</h1>
        <p>Serves&nbsp;4</p>
        <ul><li>1 cup flour</li><li>1 egg</li><li>1 &frac12; cups milk</li></ul>
        <div>Whisk<br>together.</div>
        <!-- comment -->
        <footer>© 2026</footer>
        </body></html>
        """
        let result = x.extract(from: html)
        XCTAssertEqual(result.title, "Best & Easiest Pancakes | Site")
        XCTAssertEqual(result.text.components(separatedBy: "\n"), [
            "Best & Easiest Pancakes", "Serves 4", "1 cup flour", "1 egg", "1 ½ cups milk", "Whisk", "together.",
        ])
    }

    func testEntityDecoding() {
        XCTAssertEqual(HTMLTextExtractor.decodeEntities("&#189; cup &amp; &#x00BC; tsp &lt;b&gt;"), "½ cup & ¼ tsp <b>")
    }

    func testFeedsThePlainTextParser() throws {
        let html = "<h1>Toast</h1><h2>Ingredients</h2><ul><li>2 slices bread</li><li>1 tbsp butter</li></ul><h2>Method</h2><ol><li>Toast it.</li></ol>"
        let text = x.extract(from: html).text
        let draft = try XCTUnwrap(PlainTextRecipeParser().parse(text))
        XCTAssertEqual(draft.title, "Toast")
        XCTAssertEqual(draft.ingredientLines, ["2 slices bread", "1 tbsp butter"])
        XCTAssertEqual(draft.steps, ["Toast it."])
    }
}

final class FallbackQueryInterpreterTests: XCTestCase {

    private struct Failing: QueryInterpreter {
        func interpret(_ message: String, refining current: SearchQuery?) async throws -> SearchQuery {
            throw URLError(.notConnectedToInternet)
        }
    }

    private struct Fixed: QueryInterpreter {
        func interpret(_ message: String, refining current: SearchQuery?) async throws -> SearchQuery {
            SearchQuery(text: "from model")
        }
    }

    func testUsesPrimaryWhenItWorks() async throws {
        let q = try await FallbackQueryInterpreter(primary: Fixed()).interpret("anything", refining: nil)
        XCTAssertEqual(q.text, "from model")
    }

    func testFallsBackWhenPrimaryFails() async throws {
        let q = try await FallbackQueryInterpreter(primary: Failing()).interpret("no dairy", refining: nil)
        XCTAssertEqual(q.excludeIngredients, ["dairy"])
    }

    func testFallsBackWhenNoPrimary() async throws {
        let q = try await FallbackQueryInterpreter(primary: nil).interpret("quick", refining: nil)
        XCTAssertEqual(q.maxMinutes, 30)
    }
}
