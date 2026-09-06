import XCTest
@testable import ProportionCore

private func makeRecipe(_ title: String, ingredients: [String], macros: Macros?, minutes: Int?, tags: Set<String> = []) -> Recipe {
    Recipe(
        title: title,
        baseServings: 1,
        ingredients: ingredients.map { Ingredient(name: $0) },
        cookMinutes: minutes,
        totalMacros: macros,
        tags: tags)
}

private let library: [Recipe] = [
    makeRecipe("Chicken Stir Fry", ingredients: ["chicken breast", "broccoli", "soy sauce", "rice"], macros: Macros(protein: 40, fat: 10, carbs: 45), minutes: 25, tags: ["dinner"]),
    makeRecipe("Cheesy Pasta Bake", ingredients: ["penne", "cheddar", "cream", "bacon"], macros: Macros(protein: 22, fat: 30, carbs: 60), minutes: 50, tags: ["dinner", "comfort"]),
    makeRecipe("Greek Yogurt Bowl", ingredients: ["greek yogurt", "blueberries", "honey", "almonds"], macros: Macros(protein: 20, fat: 8, carbs: 30), minutes: 5, tags: ["breakfast"]),
    makeRecipe("Tofu Scramble", ingredients: ["tofu", "spinach", "olive oil", "turmeric"], macros: Macros(protein: 18, fat: 12, carbs: 6), minutes: 15, tags: ["breakfast", "vegan"]),
    makeRecipe("Mystery Stew", ingredients: ["beef", "carrot"], macros: nil, minutes: nil),
]

final class SearchEngineTests: XCTestCase {

    private let engine = SearchEngine()

    private func titles(_ query: SearchQuery, profile: DietaryProfile? = nil) -> [String] {
        engine.search(library, query: query, profile: profile).matches.map(\.title)
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertEqual(titles(SearchQuery()).count, library.count)
    }

    func testTextSearchesTitlesAndIngredients() {
        XCTAssertEqual(titles(SearchQuery(text: "pasta")), ["Cheesy Pasta Bake"])
        XCTAssertEqual(titles(SearchQuery(text: "spinach")), ["Tofu Scramble"])
        XCTAssertEqual(titles(SearchQuery(text: "chicken rice")), ["Chicken Stir Fry"])
    }

    func testIncludeWalksTaxonomy() {
        XCTAssertEqual(titles(SearchQuery(includeIngredients: ["chicken"])), ["Chicken Stir Fry"])
        XCTAssertEqual(titles(SearchQuery(includeIngredients: ["poultry"])), ["Chicken Stir Fry"])
        XCTAssertEqual(titles(SearchQuery(includeIngredients: ["dairy"])), ["Cheesy Pasta Bake", "Greek Yogurt Bowl"])
    }

    func testExcludeWalksTaxonomy() {
        let noDairy = titles(SearchQuery(excludeIngredients: ["dairy"]))
        XCTAssertEqual(noDairy, ["Chicken Stir Fry", "Tofu Scramble", "Mystery Stew"])
        let noGluten = titles(SearchQuery(excludeIngredients: ["gluten"]))
        XCTAssertFalse(noGluten.contains("Chicken Stir Fry"), "soy sauce contains wheat")
        XCTAssertFalse(noGluten.contains("Cheesy Pasta Bake"))
    }

    func testMacroConstraintsRequireNutrition() {
        XCTAssertEqual(titles(SearchQuery(minProtein: 30)), ["Chicken Stir Fry"])
        XCTAssertEqual(titles(SearchQuery(maxCarbs: 20)), ["Tofu Scramble"])
        XCTAssertEqual(titles(SearchQuery(maxCalories: 300)), ["Greek Yogurt Bowl", "Tofu Scramble"])
        XCTAssertFalse(titles(SearchQuery(minProtein: 0)).contains("Mystery Stew"), "no nutrition → cannot satisfy a macro constraint")
    }

    func testTimeConstraint() {
        XCTAssertEqual(titles(SearchQuery(maxMinutes: 20)), ["Greek Yogurt Bowl", "Tofu Scramble"])
        XCTAssertFalse(titles(SearchQuery(maxMinutes: 500)).contains("Mystery Stew"), "unknown time never satisfies a limit")
    }

    func testTagsAndMealType() {
        XCTAssertEqual(titles(SearchQuery(mealType: "breakfast")), ["Greek Yogurt Bowl", "Tofu Scramble"])
        XCTAssertEqual(titles(SearchQuery(tags: ["Comfort"])), ["Cheesy Pasta Bake"])
    }

    func testCombinedQuery() {
        let q = SearchQuery(excludeIngredients: ["dairy"], minProtein: 30, maxMinutes: 30, mealType: "dinner")
        XCTAssertEqual(titles(q), ["Chicken Stir Fry"])
    }

    // MARK: Zero results

    func testRelaxationNamesTheClosestTime() {
        let q = SearchQuery(maxMinutes: 3)
        let result = engine.search(library, query: q)
        XCTAssertTrue(result.matches.isEmpty)
        let relaxation = try! XCTUnwrap(result.relaxation)
        XCTAssertEqual(relaxation.chip.kind, .time)
        XCTAssertEqual(relaxation.message, "Nothing under 3 minutes — the closest is 5.")
        XCTAssertNil(relaxation.relaxedQuery.maxMinutes)
    }

    func testRelaxationPicksTheConstraintThatFreesTheMost() {
        // Time limit alone frees 2; protein floor alone frees 1. Drop the time.
        let q = SearchQuery(minProtein: 30, maxMinutes: 10)
        let result = engine.search(library, query: q)
        XCTAssertTrue(result.matches.isEmpty)
        let relaxation = try! XCTUnwrap(result.relaxation)
        XCTAssertEqual(relaxation.chip.kind, .protein)
        XCTAssertEqual(relaxation.resultCount, 1)
        XCTAssertEqual(relaxation.message, "Nothing with at least 30g protein — the highest is 20g.")
    }

    func testRelaxationForExclusion() {
        let onlyTofu = library.filter { $0.title == "Tofu Scramble" }
        let result = engine.search(onlyTofu, query: SearchQuery(excludeIngredients: ["soy"]))
        let relaxation = try! XCTUnwrap(result.relaxation)
        XCTAssertEqual(relaxation.chip.kind, .exclude)
        XCTAssertEqual(relaxation.message, "Everything here has soy — 1 recipe if you allow it.")
    }

    func testRelaxationForInclusion() {
        let result = engine.search(library, query: SearchQuery(includeIngredients: ["dragonfruit"]))
        XCTAssertTrue(result.matches.isEmpty)
        let relaxation = try! XCTUnwrap(result.relaxation)
        XCTAssertEqual(relaxation.chip.kind, .include)
        XCTAssertEqual(relaxation.message, "Nothing with dragonfruit — 5 recipes without that requirement.")
    }

    func testNoRelaxationWhenNoSingleConstraintHelps() {
        // Dropping either requirement still leaves the other unmet.
        let result = engine.search(library, query: SearchQuery(includeIngredients: ["dragonfruit", "durian"]))
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertNil(result.relaxation)
    }

    // MARK: Dietary profile

    func testProfileHidesAndCounts() {
        let profile = DietaryProfile(presets: [.vegetarian])
        let result = engine.search(library, query: SearchQuery(), profile: profile)
        XCTAssertEqual(result.matches.map(\.title), ["Greek Yogurt Bowl", "Tofu Scramble"], "chicken, bacon, beef are hidden; pasta bake has bacon")
        XCTAssertEqual(result.hiddenByProfile.count, 3)
    }

    func testRelaxationIsComputedInsideTheProfile() {
        // Only the tofu scramble is vegan. Dropping the protein floor frees it —
        // and nothing else, because the profile is never a candidate to drop.
        let profile = DietaryProfile(presets: [.vegan])
        let result = engine.search(library, query: SearchQuery(minProtein: 100), profile: profile)
        XCTAssertTrue(result.matches.isEmpty)
        let relaxation = try! XCTUnwrap(result.relaxation)
        XCTAssertEqual(relaxation.chip.kind, .protein)
        XCTAssertEqual(relaxation.resultCount, 1)
        XCTAssertEqual(relaxation.message, "Nothing with at least 100g protein — the highest is 18g.")
    }
}

final class SearchQueryTests: XCTestCase {

    func testChipsRenderEveryConstraint() {
        let q = SearchQuery(text: "curry", includeIngredients: ["chicken"], excludeIngredients: ["dairy"],
                            minProtein: 30, maxCarbs: 20, maxCalories: 500, maxMinutes: 30, tags: ["weeknight"], mealType: "dinner")
        XCTAssertEqual(q.chips.map(\.label), [
            "“curry”", "with: chicken", "excludes: dairy", "protein ≥ 30g", "carbs ≤ 20g", "≤ 500 kcal", "≤ 30 min", "dinner", "#weeknight",
        ])
    }

    func testRangeLabels() {
        XCTAssertEqual(SearchQuery.rangeLabel("protein", 20, 40), "protein 20–40g")
        XCTAssertEqual(SearchQuery.rangeLabel("fat", nil, 12.5), "fat ≤ 12.5g")
        XCTAssertNil(SearchQuery.rangeLabel("fat", nil, nil))
    }

    func testRemovingChips() {
        let q = SearchQuery(includeIngredients: ["chicken", "rice"], excludeIngredients: ["dairy"], minProtein: 30, maxMinutes: 30)
        let chips = q.chips
        let withoutRice = q.removing(chips.first { $0.value == "rice" }!)
        XCTAssertEqual(withoutRice.includeIngredients, ["chicken"])
        let withoutProtein = q.removing(chips.first { $0.kind == .protein }!)
        XCTAssertNil(withoutProtein.minProtein)
        let withoutTime = q.removing(chips.first { $0.kind == .time }!)
        XCTAssertNil(withoutTime.maxMinutes)
        XCTAssertEqual(withoutTime.excludeIngredients, ["dairy"], "other constraints untouched")
    }

    func testMergeRefines() {
        var q = SearchQuery(excludeIngredients: ["dairy"], minProtein: 30, maxMinutes: 30)
        q.merge(SearchQuery(excludeIngredients: ["chicken"], maxMinutes: 20))
        XCTAssertEqual(q.excludeIngredients, ["dairy", "chicken"])
        XCTAssertEqual(q.maxMinutes, 20)
        XCTAssertEqual(q.minProtein, 30)
    }

    func testMergeExcludingSomethingRequiredDropsTheRequirement() {
        var q = SearchQuery(includeIngredients: ["chicken"])
        q.merge(SearchQuery(excludeIngredients: ["chicken"]))
        XCTAssertEqual(q.includeIngredients, [])
        XCTAssertEqual(q.excludeIngredients, ["chicken"])
    }

    func testIsEmpty() {
        XCTAssertTrue(SearchQuery().isEmpty)
        XCTAssertFalse(SearchQuery(maxMinutes: 5).isEmpty)
    }

    func testCodableRoundTrip() throws {
        let q = SearchQuery(text: "x", includeIngredients: ["a"], excludeIngredients: ["b"], minProtein: 1, maxMinutes: 2, tags: ["t"], mealType: "lunch")
        let data = try JSONEncoder().encode(q)
        XCTAssertEqual(try JSONDecoder().decode(SearchQuery.self, from: data), q)
    }
}

final class KeywordQueryInterpreterTests: XCTestCase {

    private let k = KeywordQueryInterpreter()

    func testTheSpecExample() {
        let q = k.parse("high protein dinner, no dairy, under 30 minutes")
        XCTAssertEqual(q.minProtein, 30)
        XCTAssertEqual(q.mealType, "dinner")
        XCTAssertEqual(q.excludeIngredients, ["dairy"])
        XCTAssertEqual(q.maxMinutes, 30)
        XCTAssertNil(q.text)
    }

    func testTheOtherSpecExample() {
        let q = k.parse("something with the chicken thighs I have, but I'm sick of rice")
        XCTAssertEqual(q.includeIngredients, ["chicken thigh"])
        XCTAssertEqual(q.excludeIngredients, ["rice"])
    }

    func testListsOfIngredients() {
        XCTAssertEqual(k.parse("no dairy or nuts").excludeIngredients, ["dairy", "nut"])
        XCTAssertEqual(k.parse("without peanuts, shellfish and eggs").excludeIngredients, ["peanut", "shellfish", "egg"])
        XCTAssertEqual(k.parse("with chicken and broccoli").includeIngredients, ["chicken", "broccoli"])
    }

    func testListStopsAtUnknownWords() {
        let q = k.parse("no dairy and high protein")
        XCTAssertEqual(q.excludeIngredients, ["dairy"])
        XCTAssertEqual(q.minProtein, 30)
    }

    func testNumericMacros() {
        let q = k.parse("at least 40g protein and under 500 calories")
        XCTAssertEqual(q.minProtein, 40)
        XCTAssertEqual(q.maxCalories, 500)
        XCTAssertEqual(k.parse("under 20g carbs").maxCarbs, 20)
        XCTAssertEqual(k.parse("30g+ protein").minProtein, 30)
        XCTAssertEqual(k.parse("protein over 35").minProtein, 35)
        XCTAssertEqual(k.parse("less than 10 grams of fat").maxFat, 10)
        XCTAssertEqual(k.parse("50 carbs").maxCarbs, 50, "bare carbs default to a ceiling")
        XCTAssertEqual(k.parse("50 protein").minProtein, 50, "bare protein defaults to a floor")
    }

    func testMacroPhrases() {
        XCTAssertEqual(k.parse("low carb").maxCarbs, 20)
        XCTAssertEqual(k.parse("keto").maxCarbs, 10)
        XCTAssertEqual(k.parse("low-fat").maxFat, 15)
        XCTAssertEqual(k.parse("something light").maxCalories, 400)
    }

    func testTime() {
        XCTAssertEqual(k.parse("in 20 minutes").maxMinutes, 20)
        XCTAssertEqual(k.parse("ready in 1 hour").maxMinutes, 60)
        XCTAssertEqual(k.parse("quick lunch").maxMinutes, 30)
        XCTAssertEqual(k.parse("quick lunch").mealType, "lunch")
        XCTAssertEqual(k.parse("45 mins or less").maxMinutes, 45)
    }

    func testDietPresets() {
        XCTAssertTrue(k.parse("vegan dinner").excludeIngredients.contains("dairy"))
        XCTAssertTrue(k.parse("vegan dinner").excludeIngredients.contains("meat"))
        XCTAssertEqual(k.parse("gluten-free breakfast").excludeIngredients, ["gluten"])
        XCTAssertEqual(k.parse("gluten-free breakfast").mealType, "breakfast")
        XCTAssertEqual(k.parse("nut free").excludeIngredients, ["nut"])
        XCTAssertEqual(k.parse("dairy free and egg free").excludeIngredients, ["dairy", "egg"])
    }

    func testFreeTextFallback() {
        let q = k.parse("lasagna")
        XCTAssertEqual(q.text, "lasagna")
        XCTAssertEqual(q.chips.count, 1)
    }

    func testRefinement() {
        let first = k.parse("high protein, no dairy")
        let second = k.parse("actually no chicken either", refining: first)
        XCTAssertEqual(second.excludeIngredients, ["dairy", "chicken"])
        XCTAssertEqual(second.minProtein, 30)
    }

    func testReset() {
        let current = SearchQuery(minProtein: 30)
        XCTAssertTrue(k.parse("reset", refining: current).isEmpty)
        XCTAssertTrue(k.parse("Start over", refining: current).isEmpty)
    }

    func testAsyncConformance() async throws {
        let interpreter: any QueryInterpreter = k
        let q = try await interpreter.interpret("no dairy", refining: nil)
        XCTAssertEqual(q.excludeIngredients, ["dairy"])
    }
}

final class DietaryProfileTests: XCTestCase {

    func testPresetsExpand() {
        let p = DietaryProfile(presets: [.vegetarian, .nutFree], customExclusions: ["cilantro"])
        XCTAssertEqual(p.allExclusions, ["meat", "fish", "shellfish", "gelatin", "nut", "cilantro"])
    }

    func testViolationsAndAllows() {
        let p = DietaryProfile(presets: [.dairyFree])
        let carbonara = Recipe(title: "Carbonara", baseServings: 2, ingredients: [
            Ingredient(name: "spaghetti"), Ingredient(name: "pecorino romano"), Ingredient(name: "eggs"),
        ])
        XCTAssertEqual(p.violations(in: carbonara).map(\.name), ["pecorino romano"])
        XCTAssertFalse(p.allows(carbonara))
        XCTAssertTrue(DietaryProfile.empty.allows(carbonara))
    }

    func testChipsAreLocked() {
        let p = DietaryProfile(presets: [.vegan], customExclusions: ["cilantro"])
        let chips = p.chips
        XCTAssertEqual(chips.map(\.label), ["Vegan", "no cilantro"])
        XCTAssertTrue(chips.allSatisfy(\.isLocked))
        XCTAssertTrue(chips.allSatisfy { $0.kind == .profile })
    }

    func testDisclaimerNeverClaimsSafety() {
        let text = DietaryProfile.disclaimer.lowercased()
        XCTAssertFalse(text.contains("safe"))
        XCTAssertFalse(text.contains("free from"))
        XCTAssertTrue(text.contains("not a substitute"))
    }

    func testCodable() throws {
        let p = DietaryProfile(presets: [.glutenFree], customExclusions: ["mushroom"])
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(DietaryProfile.self, from: data), p)
    }
}
