import XCTest
@testable import ProportionCore

final class JSONLDRecipeExtractorTests: XCTestCase {

    private let x = JSONLDRecipeExtractor()

    private let graphPage = """
    <html><head>
    <script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[
      {"@type":"WebSite","name":"Example Kitchen"},
      {"@type":["Recipe","NewsArticle"],
       "name":"Weeknight Chicken Bake",
       "author":{"@type":"Person","name":"Jo Cook"},
       "url":"https://example.com/chicken-bake",
       "image":["https://example.com/a.jpg","https://example.com/b.jpg"],
       "recipeYield":["4","4 servings"],
       "prepTime":"PT15M","cookTime":"PT1H30M",
       "recipeIngredient":["500g chicken thighs","2 cups all-purpose flour, sifted","salt to taste"],
       "recipeInstructions":[
         {"@type":"HowToSection","name":"Prep","itemListElement":[{"@type":"HowToStep","text":"Preheat the oven to <b>200C</b>."}]},
         {"@type":"HowToStep","text":"Bake for 90 minutes."}
       ],
       "nutrition":{"@type":"NutritionInformation","calories":"420 kcal","proteinContent":"32 g","fatContent":"12.5 g","carbohydrateContent":"40 g"}
      }
    ]}
    </script>
    </head><body>hello</body></html>
    """

    func testExtractsRecipeFromGraph() throws {
        let draft = try XCTUnwrap(x.extract(fromHTML: graphPage))
        XCTAssertEqual(draft.title, "Weeknight Chicken Bake")
        XCTAssertEqual(draft.source, .jsonLD)
        XCTAssertEqual(draft.sourceAttribution, "Jo Cook")
        XCTAssertEqual(draft.sourceURL?.absoluteString, "https://example.com/chicken-bake")
        XCTAssertEqual(draft.imageURL?.absoluteString, "https://example.com/a.jpg")
        XCTAssertEqual(draft.servings, 4)
        XCTAssertEqual(draft.prepMinutes, 15)
        XCTAssertEqual(draft.cookMinutes, 90)
        XCTAssertEqual(draft.ingredientLines, ["500g chicken thighs", "2 cups all-purpose flour, sifted", "salt to taste"])
        XCTAssertEqual(draft.steps, ["Preheat the oven to 200C.", "Bake for 90 minutes."])
        XCTAssertEqual(draft.perServingMacros, Macros(protein: 32, fat: 12.5, carbs: 40))
        XCTAssertEqual(draft.nutritionConfidence, .estimated)
        XCTAssertTrue(draft.warnings.isEmpty)
    }

    func testDraftBecomesRecipe() throws {
        let draft = try XCTUnwrap(x.extract(fromHTML: graphPage))
        let (recipe, warnings) = draft.makeRecipe()
        XCTAssertTrue(warnings.isEmpty, "\(warnings)")
        XCTAssertEqual(recipe.baseServings, 4)
        XCTAssertEqual(recipe.ingredients.count, 3)
        XCTAssertEqual(recipe.ingredients[0].quantity, Quantity(500, .gram))
        XCTAssertEqual(recipe.ingredients[1].preparation, "sifted")
        XCTAssertEqual(recipe.ingredients[2].descriptor, "to taste")
        XCTAssertTrue(recipe.ingredients[0].categoryTags.contains("poultry"))
        XCTAssertTrue(recipe.ingredients[1].categoryTags.contains("gluten"))
        XCTAssertEqual(try XCTUnwrap(recipe.totalMacros).protein, 128, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(recipe.perServingMacros).protein, 32, accuracy: 1e-9)
        XCTAssertEqual(recipe.nutritionConfidence, .estimated)
    }

    func testTopLevelRecipeWithStringInstructionsAndNumericYield() throws {
        let html = """
        <script type='application/ld+json'>
        {"@context":"https://schema.org/","@type":"Recipe","name":"Toast",
         "recipeYield":2,"recipeIngredient":["2 slices bread"],
         "recipeInstructions":"Toast the bread.\\nButter it."}
        </script>
        """
        let draft = try XCTUnwrap(x.extract(fromHTML: html))
        XCTAssertEqual(draft.servings, 2)
        XCTAssertEqual(draft.steps, ["Toast the bread.", "Butter it."])
        XCTAssertNil(draft.perServingMacros)
        XCTAssertEqual(draft.nutritionConfidence, .unknown)
    }

    func testMissingServingsProducesWarningOnMakeRecipe() throws {
        let html = """
        <script type="application/ld+json">{"@type":"Recipe","name":"Mystery","recipeIngredient":["1 egg"]}</script>
        """
        let draft = try XCTUnwrap(x.extract(fromHTML: html))
        XCTAssertNil(draft.servings)
        let (recipe, warnings) = draft.makeRecipe()
        XCTAssertEqual(recipe.baseServings, RecipeDraft.assumedServings)
        XCTAssertEqual(warnings.count, 2, "assumed servings + no instructions")
    }

    func testPagesWithoutRecipesReturnNil() {
        XCTAssertNil(x.extract(fromHTML: "<html><body>Nothing here</body></html>"))
        let article = """
        <script type="application/ld+json">{"@type":"NewsArticle","name":"Not food"}</script>
        """
        XCTAssertNil(x.extract(fromHTML: article))
    }

    func testMalformedBlocksAreSkipped() throws {
        let html = """
        <script type="application/ld+json">{ this is not json</script>
        <script type="application/ld+json">{"@type":"Recipe","name":"Good","recipeYield":"Serves 6","recipeIngredient":["1 cup rice"]}</script>
        """
        let draft = try XCTUnwrap(x.extract(fromHTML: html))
        XCTAssertEqual(draft.title, "Good")
        XCTAssertEqual(draft.servings, 6)
    }

    func testCDATAIsStripped() throws {
        let html = """
        <script type="application/ld+json"><![CDATA[{"@type":"Recipe","name":"Wrapped","recipeIngredient":["1 egg"]}]]></script>
        """
        XCTAssertEqual(x.extract(fromHTML: html)?.title, "Wrapped")
    }

    func testPageURLIsFallbackSource() throws {
        let html = """
        <script type="application/ld+json">{"@type":"Recipe","name":"X","recipeIngredient":["1 egg"]}</script>
        """
        let page = URL(string: "https://cooks.example/x")!
        let draft = try XCTUnwrap(x.extract(fromHTML: html, pageURL: page))
        XCTAssertEqual(draft.sourceURL, page)
        XCTAssertEqual(draft.sourceAttribution, "cooks.example")
    }

    // MARK: Helpers

    func testISO8601Durations() {
        XCTAssertEqual(JSONLDRecipeExtractor.minutes(fromISO8601: "PT30M"), 30)
        XCTAssertEqual(JSONLDRecipeExtractor.minutes(fromISO8601: "PT1H30M"), 90)
        XCTAssertEqual(JSONLDRecipeExtractor.minutes(fromISO8601: "PT1H"), 60)
        XCTAssertEqual(JSONLDRecipeExtractor.minutes(fromISO8601: "P0DT0H45M"), 45)
        XCTAssertEqual(JSONLDRecipeExtractor.minutes(fromISO8601: "P1D"), 1440)
        XCTAssertEqual(JSONLDRecipeExtractor.minutes(fromISO8601: "PT90S"), 2)
        XCTAssertNil(JSONLDRecipeExtractor.minutes(fromISO8601: "PT0M"))
        XCTAssertNil(JSONLDRecipeExtractor.minutes(fromISO8601: "30 minutes"))
        XCTAssertNil(JSONLDRecipeExtractor.minutes(fromISO8601: nil))
    }

    func testYieldParsing() {
        XCTAssertEqual(JSONLDRecipeExtractor.yield(from: "4"), 4)
        XCTAssertEqual(JSONLDRecipeExtractor.yield(from: "4 servings"), 4)
        XCTAssertEqual(JSONLDRecipeExtractor.yield(from: "Serves 6-8"), 6)
        XCTAssertEqual(JSONLDRecipeExtractor.yield(from: "Makes 12 muffins"), 12)
        XCTAssertNil(JSONLDRecipeExtractor.yield(from: "a few"))
        XCTAssertNil(JSONLDRecipeExtractor.yield(from: "0"))
    }

    func testNutritionNumberParsing() {
        XCTAssertEqual(JSONLDRecipeExtractor.firstDouble(in: "12.5 g"), 12.5)
        XCTAssertEqual(JSONLDRecipeExtractor.firstDouble(in: "12,5 g"), 12.5)
        XCTAssertEqual(JSONLDRecipeExtractor.firstDouble(in: "32 grams"), 32)
        XCTAssertNil(JSONLDRecipeExtractor.firstDouble(in: "n/a"))
    }

    func testHTMLStripping() {
        XCTAssertEqual(JSONLDRecipeExtractor.stripHTML("Preheat to <b>200C</b> &amp; wait"), "Preheat to 200C & wait")
    }
}
