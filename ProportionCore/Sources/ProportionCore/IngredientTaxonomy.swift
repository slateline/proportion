import Foundation

/// Resolves ingredient text to a canonical name and walks it up a category
/// hierarchy: parmesan → hard cheese → cheese → dairy.
///
/// This is what makes exclusion search work. Naive string matching fails in
/// exactly the cases that matter most — excluding "dairy" must catch butter,
/// cream and parmesan; excluding "peanut" must catch peanut butter and satay
/// sauce; and excluding "butter" must *not* catch peanut butter. The taxonomy
/// is a bundled, deterministic dataset, never a model call at query time.
///
/// It is deliberately over-inclusive: an exclusion filter that occasionally
/// hides a safe recipe is a nuisance; one that shows an unsafe one is a harm.
/// Even so, this is a convenience filter and is never presented as allergen
/// safety — see the spec.
public struct IngredientTaxonomy: Sendable {
    /// Canonical name → its direct parent categories.
    public let parents: [String: [String]]
    /// Alternate spelling or regional name → canonical name.
    public let aliases: [String: String]

    /// Every term we can recognise in free text, longest first so that
    /// "peanut butter" is tried before "butter".
    private let knownTerms: [String]

    public init(parents: [String: [String]], aliases: [String: String]) {
        var normalisedParents: [String: [String]] = [:]
        for (key, value) in parents {
            normalisedParents[Self.normalise(key)] = value.map(Self.normalise)
        }
        var normalisedAliases: [String: String] = [:]
        for (key, value) in aliases {
            normalisedAliases[Self.normalise(key)] = Self.normalise(value)
        }
        self.parents = normalisedParents
        self.aliases = normalisedAliases

        var terms = Set(normalisedParents.keys)
        terms.formUnion(normalisedAliases.keys)
        for list in normalisedParents.values { terms.formUnion(list) }
        self.knownTerms = terms.sorted { a, b in
            a.count != b.count ? a.count > b.count : a < b
        }
    }

    /// The built-in dataset.
    public static let standard = IngredientTaxonomy(
        parents: TaxonomyData.parents,
        aliases: TaxonomyData.aliases
    )

    // MARK: Resolution

    /// Maps free text to a canonical name. Unknown ingredients come back
    /// normalised but otherwise unchanged, so they still match themselves.
    public func canonicalName(for text: String) -> String {
        let normalised = Self.normalise(text)
        if normalised.isEmpty { return normalised }

        if let direct = resolve(normalised) { return direct }

        // Longest known term that appears as whole words, in either the text
        // as written or with each word singularised ("egg whites" → "egg white").
        let padded = " \(normalised) "
        let singularPadded = " \(Self.singularisedWords(normalised)) "
        for term in knownTerms {
            let needle = " \(term) "
            if padded.contains(needle) || singularPadded.contains(needle) {
                return resolve(term) ?? term
            }
        }
        return normalised
    }

    /// Exact-match resolution of an already-normalised string through the
    /// alias table and known names, tolerating a simple plural.
    private func resolve(_ normalised: String) -> String? {
        if let alias = aliases[normalised] { return alias }
        if parents[normalised] != nil { return normalised }
        let singular = Self.singularisedWords(normalised)
        if singular != normalised {
            if let alias = aliases[singular] { return alias }
            if parents[singular] != nil { return singular }
        }
        return nil
    }

    /// Every category above `canonical`, transitively. Does not include the
    /// name itself.
    public func ancestors(of canonical: String) -> Set<String> {
        var seen: Set<String> = []
        var queue = parents[Self.normalise(canonical)] ?? []
        while let next = queue.first {
            queue.removeFirst()
            guard seen.insert(next).inserted else { continue }
            queue.append(contentsOf: parents[next] ?? [])
        }
        return seen
    }

    /// The canonical name plus all of its ancestors — the full set of
    /// exclusion terms that should hit this ingredient.
    public func tags(for text: String) -> Set<String> {
        let canonical = canonicalName(for: text)
        var result = ancestors(of: canonical)
        result.insert(canonical)
        return result
    }

    // MARK: Ingredients and recipes

    /// A copy of `ingredient` with `categoryTags` filled in from its name.
    /// Tags the parser or user already added are kept.
    public func tagged(_ ingredient: Ingredient) -> Ingredient {
        var copy = ingredient
        copy.categoryTags.formUnion(tags(for: ingredient.name))
        return copy
    }

    /// Every exclusion term that should hit this ingredient: what its name
    /// resolves to, plus any tags the parser or user attached, each walked up
    /// the hierarchy so a pre-tag of "fish" also answers to "seafood".
    public func allTags(of ingredient: Ingredient) -> Set<String> {
        var result = tags(for: ingredient.name)
        for tag in ingredient.categoryTags {
            let canonical = Self.normalise(tag)
            result.insert(canonical)
            result.formUnion(ancestors(of: canonical))
        }
        return result
    }

    /// Whether excluding `exclusion` should hide this ingredient.
    public func ingredient(_ ingredient: Ingredient, matches exclusion: String) -> Bool {
        allTags(of: ingredient).contains(canonicalName(for: exclusion))
    }

    /// Ingredients in `recipe` that hit any of `exclusions`, in recipe order.
    public func violations(in recipe: Recipe, excluding exclusions: Set<String>) -> [Ingredient] {
        let targets = Set(exclusions.map(canonicalName(for:)))
        guard !targets.isEmpty else { return [] }
        return recipe.ingredients.filter { !allTags(of: $0).isDisjoint(with: targets) }
    }

    // MARK: Text normalisation

    /// Lowercase, strip punctuation, collapse whitespace.
    static func normalise(_ text: String) -> String {
        var scalars: [Character] = []
        var lastWasSpace = true
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" {
                scalars.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                scalars.append(" ")
                lastWasSpace = true
            }
        }
        var result = String(scalars)
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// A deliberately simple English singulariser applied per word. It only
    /// has to be good enough to map recipe plurals onto the dataset.
    static func singularise(_ word: String) -> String {
        if word.count <= 3 { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") || word.hasSuffix("ches") || word.hasSuffix("shes")
            || word.hasSuffix("xes") || word.hasSuffix("sses") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ss") || word.hasSuffix("us") { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    static func singularisedWords(_ text: String) -> String {
        text.split(separator: " ").map { singularise(String($0)) }.joined(separator: " ")
    }
}
