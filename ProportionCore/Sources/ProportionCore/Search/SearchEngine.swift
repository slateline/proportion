import Foundation

public struct SearchResult: Hashable, Sendable {
    public var matches: [Recipe]
    /// Recipes that matched the query but violate the dietary profile.
    public var hiddenByProfile: [Recipe]
    /// When nothing matched: the single constraint whose removal helps most.
    public var relaxation: Relaxation?
}

public struct Relaxation: Hashable, Sendable {
    public let chip: QueryChip
    /// "Nothing under 20 minutes — the closest is 35."
    public let message: String
    public let resultCount: Int
    public let relaxedQuery: SearchQuery
}

/// Runs a `SearchQuery` against the library as a plain local predicate.
/// Nothing here is probabilistic: the same query over the same recipes
/// always gives the same answer, and it works offline.
public struct SearchEngine: Sendable {
    public var taxonomy: IngredientTaxonomy

    public init(taxonomy: IngredientTaxonomy = .standard) {
        self.taxonomy = taxonomy
    }

    // MARK: Matching

    public func matches(_ recipe: Recipe, query: SearchQuery) -> Bool {
        if let text = query.text, !text.isEmpty {
            let haystack = ([recipe.title] + recipe.ingredients.map(\.name)).joined(separator: " ").lowercased()
            let words = text.lowercased().split(separator: " ").map(String.init)
            guard words.allSatisfy({ haystack.contains($0) }) else { return false }
        }

        for required in query.includeIngredients {
            let target = taxonomy.canonicalName(for: required)
            guard recipe.ingredients.contains(where: { taxonomy.allTags(of: $0).contains(target) }) else { return false }
        }

        if !query.excludeIngredients.isEmpty,
           !taxonomy.violations(in: recipe, excluding: Set(query.excludeIngredients)).isEmpty {
            return false
        }

        if query.hasMacroConstraint {
            guard let m = recipe.perServingMacros else { return false }
            if let v = query.minProtein, m.protein < v { return false }
            if let v = query.maxProtein, m.protein > v { return false }
            if let v = query.minCarbs, m.carbs < v { return false }
            if let v = query.maxCarbs, m.carbs > v { return false }
            if let v = query.minFat, m.fat < v { return false }
            if let v = query.maxFat, m.fat > v { return false }
            if let v = query.maxCalories, m.calories > v { return false }
        }

        if let maxMinutes = query.maxMinutes {
            guard let total = recipe.totalMinutes, total <= maxMinutes else { return false }
        }

        let recipeTags = Set(recipe.tags.map { $0.lowercased() })
        for tag in query.tags where !recipeTags.contains(tag.lowercased()) { return false }
        if let meal = query.mealType, !recipeTags.contains(meal.lowercased()) { return false }

        return true
    }

    // MARK: Search

    public func search(_ recipes: [Recipe], query: SearchQuery, profile: DietaryProfile? = nil) -> SearchResult {
        var visible: [Recipe] = []
        var hidden: [Recipe] = []
        for recipe in recipes {
            if let profile, !profile.allows(recipe, taxonomy: taxonomy) {
                hidden.append(recipe)
            } else {
                visible.append(recipe)
            }
        }

        let matched = visible.filter { matches($0, query: query) }
        let hiddenMatches = hidden.filter { matches($0, query: query) }

        var relaxation: Relaxation?
        if matched.isEmpty, !query.isEmpty {
            relaxation = bestRelaxation(of: query, over: visible)
        }
        return SearchResult(matches: matched, hiddenByProfile: hiddenMatches, relaxation: relaxation)
    }

    /// Try dropping each constraint in turn; report the one that frees the
    /// most recipes, phrased so the user knows how far off they were.
    func bestRelaxation(of query: SearchQuery, over recipes: [Recipe]) -> Relaxation? {
        var best: Relaxation?
        for chip in query.chips where chip.kind != .profile {
            let relaxed = query.removing(chip)
            let results = recipes.filter { matches($0, query: relaxed) }
            guard !results.isEmpty else { continue }
            if let current = best, current.resultCount >= results.count { continue }
            best = Relaxation(
                chip: chip,
                message: message(for: chip, query: query, results: results),
                resultCount: results.count,
                relaxedQuery: relaxed)
        }
        return best
    }

    private func message(for chip: QueryChip, query: SearchQuery, results: [Recipe]) -> String {
        let n = results.count
        let recipes = n == 1 ? "1 recipe" : "\(n) recipes"
        switch chip.kind {
        case .time:
            if let limit = query.maxMinutes, let closest = results.compactMap(\.totalMinutes).min() {
                return "Nothing under \(limit) minutes — the closest is \(closest)."
            }
        case .protein:
            if let floor = query.minProtein, let highest = results.compactMap({ $0.perServingMacros?.protein }).max() {
                return "Nothing with at least \(SearchQuery.format(floor))g protein — the highest is \(SearchQuery.format(highest.rounded()))g."
            }
        case .carbs:
            if let ceiling = query.maxCarbs, let lowest = results.compactMap({ $0.perServingMacros?.carbs }).min() {
                return "Nothing under \(SearchQuery.format(ceiling))g carbs — the lowest is \(SearchQuery.format(lowest.rounded()))g."
            }
        case .fat:
            if let ceiling = query.maxFat, let lowest = results.compactMap({ $0.perServingMacros?.fat }).min() {
                return "Nothing under \(SearchQuery.format(ceiling))g fat — the lowest is \(SearchQuery.format(lowest.rounded()))g."
            }
        case .calories:
            if let ceiling = query.maxCalories, let lowest = results.compactMap({ $0.perServingMacros?.calories }).min() {
                return "Nothing under \(SearchQuery.format(ceiling)) kcal — the lowest is \(SearchQuery.format(lowest.rounded()))."
            }
        case .exclude:
            return "Everything here has \(chip.value) — \(recipes) if you allow it."
        case .include:
            return "Nothing with \(chip.value) — \(recipes) without that requirement."
        default:
            break
        }
        return "Nothing matches \(chip.label) — \(recipes) if you drop it."
    }
}
