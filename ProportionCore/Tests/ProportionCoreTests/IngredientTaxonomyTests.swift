import XCTest
@testable import ProportionCore

final class IngredientTaxonomyTests: XCTestCase {

    private let t = IngredientTaxonomy.standard

    // MARK: Resolution

    func testExactNames() {
        XCTAssertEqual(t.canonicalName(for: "parmesan"), "parmesan")
        XCTAssertEqual(t.canonicalName(for: "Parmesan"), "parmesan")
        XCTAssertEqual(t.canonicalName(for: "  butter "), "butter")
    }

    func testAliases() {
        XCTAssertEqual(t.canonicalName(for: "Parmigiano Reggiano"), "parmesan")
        XCTAssertEqual(t.canonicalName(for: "groundnut"), "peanut")
        XCTAssertEqual(t.canonicalName(for: "scallions"), "spring onion")
        XCTAssertEqual(t.canonicalName(for: "double cream"), "heavy cream")
        XCTAssertEqual(t.canonicalName(for: "goat's cheese"), "goat cheese")
    }

    func testPlurals() {
        XCTAssertEqual(t.canonicalName(for: "eggs"), "egg")
        XCTAssertEqual(t.canonicalName(for: "tomatoes"), "tomato")
        XCTAssertEqual(t.canonicalName(for: "anchovies"), "anchovy")
        XCTAssertEqual(t.canonicalName(for: "egg whites"), "egg white")
        XCTAssertEqual(t.canonicalName(for: "chickpeas"), "chickpea")
    }

    func testLongestMatchInsideFreeText() {
        XCTAssertEqual(t.canonicalName(for: "freshly grated parmesan cheese"), "parmesan")
        XCTAssertEqual(t.canonicalName(for: "creamy peanut butter"), "peanut butter")
        XCTAssertEqual(t.canonicalName(for: "boneless skinless chicken thighs"), "chicken thigh")
        XCTAssertEqual(t.canonicalName(for: "2 large eggs, beaten"), "egg")
        XCTAssertEqual(t.canonicalName(for: "cloves of garlic"), "garlic")
    }

    func testUnknownIngredientsPassThroughNormalised() {
        XCTAssertEqual(t.canonicalName(for: "Dragonfruit"), "dragonfruit")
        XCTAssertEqual(t.tags(for: "dragonfruit"), ["dragonfruit"])
    }

    // MARK: Hierarchy

    func testWalksUpTheHierarchy() {
        let tags = t.tags(for: "parmesan")
        XCTAssertTrue(tags.isSuperset(of: ["parmesan", "hard cheese", "cheese", "dairy"]))
        XCTAssertFalse(tags.contains("meat"))
    }

    func testCompositeFoodsCarryEveryAllergen() {
        let pesto = t.tags(for: "pesto")
        XCTAssertTrue(pesto.isSuperset(of: ["pine nut", "tree nut", "nut", "parmesan", "cheese", "dairy"]))

        let soySauce = t.tags(for: "soy sauce")
        XCTAssertTrue(soySauce.isSuperset(of: ["soy", "legume", "wheat", "gluten"]))
    }

    func testPeanutIsBothLegumeAndNut() {
        let tags = t.tags(for: "peanut butter")
        XCTAssertTrue(tags.isSuperset(of: ["peanut butter", "peanut", "legume", "nut"]))
        XCTAssertFalse(tags.contains("tree nut"))
        XCTAssertFalse(tags.contains("dairy"), "peanut butter is not butter")
    }

    // MARK: The cases the spec calls out

    func testExcludingDairyCatchesButterCreamAndParmesan() {
        for name in ["butter", "cream", "parmesan", "heavy cream", "ghee", "cream cheese", "buttermilk"] {
            XCTAssertTrue(t.ingredient(Ingredient(name: name), matches: "dairy"), name)
        }
    }

    func testExcludingPeanutCatchesPeanutButterGroundnutAndSatay() {
        for name in ["peanut butter", "groundnut", "satay sauce", "groundnut oil", "roasted peanuts"] {
            XCTAssertTrue(t.ingredient(Ingredient(name: name), matches: "peanut"), name)
        }
    }

    func testExcludingButterDoesNotCatchPeanutButter() {
        XCTAssertFalse(t.ingredient(Ingredient(name: "peanut butter"), matches: "butter"))
        XCTAssertFalse(t.ingredient(Ingredient(name: "almond butter"), matches: "dairy"))
        XCTAssertFalse(t.ingredient(Ingredient(name: "cocoa butter"), matches: "dairy"))
    }

    func testPlantMilksAreNotDairy() {
        for name in ["almond milk", "oat milk", "coconut milk", "soy milk", "unsweetened almond milk"] {
            XCTAssertFalse(t.ingredient(Ingredient(name: name), matches: "dairy"), name)
        }
        XCTAssertTrue(t.ingredient(Ingredient(name: "almond milk"), matches: "nut"))
    }

    func testEggplantIsNotEgg() {
        XCTAssertFalse(t.ingredient(Ingredient(name: "eggplant"), matches: "egg"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "eggplant"), matches: "nightshade"))
    }

    func testCreamOfTartarIsNotCream() {
        XCTAssertFalse(t.ingredient(Ingredient(name: "cream of tartar"), matches: "dairy"))
    }

    func testMeatHierarchy() {
        XCTAssertTrue(t.ingredient(Ingredient(name: "chicken"), matches: "meat"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "chicken"), matches: "poultry"))
        XCTAssertFalse(t.ingredient(Ingredient(name: "chicken"), matches: "red meat"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "bacon"), matches: "pork"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "ground beef"), matches: "red meat"))
    }

    func testSeafoodHierarchy() {
        XCTAssertTrue(t.ingredient(Ingredient(name: "shrimp"), matches: "shellfish"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "shrimp"), matches: "seafood"))
        XCTAssertFalse(t.ingredient(Ingredient(name: "shrimp"), matches: "fish"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "worcestershire sauce"), matches: "fish"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "oyster sauce"), matches: "shellfish"))
    }

    func testExclusionTermsAreThemselvesCanonicalised() {
        XCTAssertTrue(t.ingredient(Ingredient(name: "peanut butter"), matches: "Groundnuts"))
        XCTAssertTrue(t.ingredient(Ingredient(name: "parmesan"), matches: "Cheese"))
    }

    func testPreTaggedIngredientsAreWalkedUpTheHierarchy() {
        let ingredient = Ingredient(name: "house special sauce", categoryTags: ["fish"])
        XCTAssertTrue(t.ingredient(ingredient, matches: "fish"))
        XCTAssertTrue(t.ingredient(ingredient, matches: "seafood"), "a pre-tag of fish implies seafood")
        XCTAssertFalse(t.ingredient(ingredient, matches: "shellfish"))
    }

    // MARK: Tagging and recipes

    func testTaggedFillsCategoryTags() {
        let tagged = t.tagged(Ingredient(name: "Freshly grated parmesan"))
        XCTAssertTrue(tagged.categoryTags.isSuperset(of: ["parmesan", "cheese", "dairy"]))
        XCTAssertEqual(tagged.name, "Freshly grated parmesan", "the display name is untouched")
    }

    func testViolationsInRecipe() {
        let recipe = Recipe(title: "Carbonara", baseServings: 2, ingredients: [
            Ingredient(name: "spaghetti"),
            Ingredient(name: "pancetta"),
            Ingredient(name: "eggs"),
            Ingredient(name: "pecorino romano"),
            Ingredient(name: "black pepper"),
        ])
        let dairy = t.violations(in: recipe, excluding: ["dairy"]).map(\.name)
        XCTAssertEqual(dairy, ["pecorino romano"])

        let glutenAndPork = t.violations(in: recipe, excluding: ["gluten", "pork"]).map(\.name)
        XCTAssertEqual(glutenAndPork, ["spaghetti", "pancetta"])

        XCTAssertTrue(t.violations(in: recipe, excluding: ["shellfish"]).isEmpty)
        XCTAssertTrue(t.violations(in: recipe, excluding: []).isEmpty)
    }

    // MARK: Dataset hygiene

    func testEveryParentReferencedIsDefined() {
        var missing: Set<String> = []
        for (_, parents) in t.parents {
            for p in parents where t.parents[p] == nil { missing.insert(p) }
        }
        XCTAssertEqual(missing, [], "parents referenced but never defined: \(missing.sorted())")
    }

    func testHierarchyHasNoCycles() {
        for key in t.parents.keys {
            XCTAssertFalse(t.ancestors(of: key).contains(key), "cycle through \(key)")
        }
    }

    // MARK: Normalisation helpers

    func testSingularise() {
        XCTAssertEqual(IngredientTaxonomy.singularise("eggs"), "egg")
        XCTAssertEqual(IngredientTaxonomy.singularise("tomatoes"), "tomato")
        XCTAssertEqual(IngredientTaxonomy.singularise("cherries"), "cherry")
        XCTAssertEqual(IngredientTaxonomy.singularise("hummus"), "hummus")
        XCTAssertEqual(IngredientTaxonomy.singularise("glasses"), "glass")
        XCTAssertEqual(IngredientTaxonomy.singularise("peas"), "pea")
        XCTAssertEqual(IngredientTaxonomy.singularise("gas"), "gas")
    }

    func testNormalise() {
        XCTAssertEqual(IngredientTaxonomy.normalise("  Sun-Dried Tomatoes, chopped! "), "sun-dried tomatoes chopped")
        XCTAssertEqual(IngredientTaxonomy.normalise("Goat's cheese"), "goat s cheese")
    }
}
