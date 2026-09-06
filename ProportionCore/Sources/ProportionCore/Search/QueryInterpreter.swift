import Foundation

/// Turns a chat message into a `SearchQuery`. The model-backed
/// implementation lives in the app; `KeywordQueryInterpreter` is the
/// deterministic offline fallback and the reference for what the structured
/// query can express.
public protocol QueryInterpreter: Sendable {
    /// `current` is the query being refined by a follow-up message, if any.
    func interpret(_ message: String, refining current: SearchQuery?) async throws -> SearchQuery
}

/// Pattern-based interpretation that needs no network. It covers the shapes
/// people actually type — "no dairy", "high protein", "under 30 minutes",
/// "with chicken", "gluten-free dinner" — and passes anything else through
/// as a title search so the user is never stuck.
public struct KeywordQueryInterpreter: QueryInterpreter, Sendable {
    public var taxonomy: IngredientTaxonomy

    public init(taxonomy: IngredientTaxonomy = .standard) {
        self.taxonomy = taxonomy
    }

    public func interpret(_ message: String, refining current: SearchQuery?) async throws -> SearchQuery {
        parse(message, refining: current)
    }

    /// Synchronous entry point; the protocol method just forwards here.
    public func parse(_ message: String, refining current: SearchQuery? = nil) -> SearchQuery {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.resetPhrases.contains(trimmed) { return SearchQuery() }

        var query = SearchQuery()
        var text = " " + trimmed.replacingOccurrences(of: "’", with: "'") + " "

        text = extractMacros(from: text, into: &query)
        text = extractTime(from: text, into: &query)
        text = extractMeal(from: text, into: &query)
        text = extractDiets(from: text, into: &query)
        text = extractFreeSuffixes(from: text, into: &query)
        text = Self.normalisePhrases(text)
        extractIngredientLists(from: text, into: &query)

        if query.isEmpty {
            query.text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let current {
            return current.merged(with: query)
        }
        return query
    }

    // MARK: Macros

    private static let macroWords = "(protein|carbs?|carbohydrates?|fat|calories?|kcal|cal)"

    private func extractMacros(from input: String, into query: inout SearchQuery) -> String {
        var text = input

        let phrases: [(String, (inout SearchQuery) -> Void)] = [
            (#"\bhigh[- ]protein\b|\bprotein[- ]rich\b|\blots of protein\b"#, { $0.minProtein = $0.minProtein ?? 30 }),
            (#"\blow[- ]carb\b"#, { $0.maxCarbs = $0.maxCarbs ?? 20 }),
            (#"\bketo\b"#, { $0.maxCarbs = $0.maxCarbs ?? 10 }),
            (#"\blow[- ]fat\b|\blean\b"#, { $0.maxFat = $0.maxFat ?? 15 }),
            (#"\blow[- ]cal(?:orie)?s?\b|\blight\b"#, { $0.maxCalories = $0.maxCalories ?? 400 }),
        ]
        for (pattern, apply) in phrases where Regex.firstMatch(pattern, in: text) != nil {
            apply(&query)
            text = Regex.replace(pattern, in: text, with: " ")
        }

        // "at least 40g protein", "under 500 calories", "protein over 30", "30g+ protein"
        let numberFirst = #"((?:at least|over|more than|min(?:imum)?|above|under|below|less than|max(?:imum)?|no more than|up to)\s+)?(\d+(?:\.\d+)?)\s*(?:g|grams?|kcal|cal)?\s*\+?\s*(?:of\s+)?"# + Self.macroWords + #"\b"#
        let macroFirst = Self.macroWords + #"\s+(over|above|at least|more than|under|below|less than|max(?:imum)?)\s+(\d+(?:\.\d+)?)\s*(?:g|grams?|kcal)?\b"#

        for groups in Regex.matches(numberFirst, in: text) {
            apply(qualifier: groups[1], value: Double(groups[2]) ?? 0, macro: groups[3], to: &query)
        }
        text = Regex.replace(numberFirst, in: text, with: " ")
        for groups in Regex.matches(macroFirst, in: text) {
            apply(qualifier: groups[2], value: Double(groups[3]) ?? 0, macro: groups[1], to: &query)
        }
        text = Regex.replace(macroFirst, in: text, with: " ")
        return text
    }

    private func apply(qualifier: String, value: Double, macro: String, to query: inout SearchQuery) {
        let q = qualifier.trimmingCharacters(in: .whitespaces)
        let isMax = ["under", "below", "less than", "max", "maximum", "no more than", "up to"].contains(q)
        let isMin = ["at least", "over", "more than", "min", "minimum", "above"].contains(q)
        switch macro.lowercased() {
        case let m where m.hasPrefix("protein"):
            if isMax { query.maxProtein = value } else { query.minProtein = value }
        case let m where m.hasPrefix("carb"):
            if isMin { query.minCarbs = value } else { query.maxCarbs = value }
        case "fat":
            if isMin { query.minFat = value } else { query.maxFat = value }
        default:
            query.maxCalories = value
        }
    }

    // MARK: Time

    private func extractTime(from input: String, into query: inout SearchQuery) -> String {
        var text = input
        let pattern = #"(?:under|less than|within|in|max(?:imum)?|up to|no more than)?\s*(\d+)\s*(min(?:ute)?s?|hours?|hrs?|h)\b(?:\s+or less)?"#
        if let groups = Regex.firstMatch(pattern, in: text), let n = Int(groups[1]) {
            let isHours = groups[2].hasPrefix("h")
            query.maxMinutes = isHours ? n * 60 : n
            text = Regex.replace(pattern, in: text, with: " ")
        } else if Regex.firstMatch(#"\b(quick|fast|speedy|in a hurry|weeknight)\b"#, in: text) != nil {
            query.maxMinutes = 30
            text = Regex.replace(#"\b(quick|fast|speedy|in a hurry|weeknight)\b"#, in: text, with: " ")
        }
        return text
    }

    // MARK: Meal type and diets

    private static let mealTypes = ["breakfast", "brunch", "lunch", "dinner", "supper", "snack", "dessert"]

    private func extractMeal(from input: String, into query: inout SearchQuery) -> String {
        var text = input
        for meal in Self.mealTypes where Regex.firstMatch(#"\b\#(meal)\b"#, in: text) != nil {
            query.mealType = meal == "supper" ? "dinner" : meal
            text = Regex.replace(#"\b(for\s+)?\#(meal)\b"#, in: text, with: " ")
            break
        }
        return text
    }

    private func extractDiets(from input: String, into query: inout SearchQuery) -> String {
        var text = input
        for preset in DietaryPreset.allCases {
            let pattern = #"\b\#(preset.keyword)\b"#
            guard Regex.firstMatch(pattern, in: text) != nil else { continue }
            for exclusion in preset.exclusions.sorted() where !query.excludeIngredients.contains(exclusion) {
                query.excludeIngredients.append(exclusion)
            }
            text = Regex.replace(pattern, in: text, with: " ")
        }
        return text
    }

    /// "dairy-free", "nut free"
    private func extractFreeSuffixes(from input: String, into query: inout SearchQuery) -> String {
        let text = input
        let pattern = #"\b([a-z]+(?:\s[a-z]+)?)[- ]free\b"#
        for groups in Regex.matches(pattern, in: text) {
            let term = taxonomy.canonicalName(for: groups[1])
            if !query.excludeIngredients.contains(term) { query.excludeIngredients.append(term) }
        }
        return Regex.replace(pattern, in: text, with: " ")
    }

    // MARK: Ingredient lists

    private static let resetPhrases: Set<String> = ["reset", "start over", "clear", "clear all", "new search", "start again"]

    /// Collapse the many ways of saying "exclude" and "include" onto two
    /// trigger words before scanning.
    static func normalisePhrases(_ input: String) -> String {
        var text = input
        let exclusionPhrases = [
            "not in the mood for", "i'm sick of", "im sick of", "sick of", "tired of", "bored of",
            "don't want", "dont want", "do not want", "without any", "without", "avoid", "avoiding",
            "skip the", "skip", "hold the", "hold", "except for", "except", "minus", "no more",
            "nothing with", "none of the", "allergic to",
        ]
        for phrase in exclusionPhrases {
            text = Regex.replace(#"\b\#(NSRegularExpression.escapedPattern(for: phrase))\b"#, in: text, with: " no ")
        }
        let inclusionPhrases = [
            "made with", "i have", "i've got", "ive got", "we have", "using", "containing", "featuring",
            "that uses", "that has", "with some", "include", "includes", "including",
        ]
        for phrase in inclusionPhrases {
            text = Regex.replace(#"\b\#(NSRegularExpression.escapedPattern(for: phrase))\b"#, in: text, with: " with ")
        }
        // Filler that would otherwise pollute ingredient phrases.
        let filler = [
            "actually", "please", "just", "really", "maybe", "i'm", "im", "i", "me", "my", "we",
            "want", "would", "like", "some", "something", "anything", "kind of", "sort of",
            "the", "a", "an", "that", "this", "tonight", "today", "tomorrow", "idea", "ideas",
            "recipe", "recipes", "meal", "meals", "dish", "dishes", "make", "cook", "eat", "have",
            "either", "too", "also", "of", "for", "to", "is", "are", "can", "could", "should",
        ]
        for word in filler {
            text = Regex.replace(#"\b\#(NSRegularExpression.escapedPattern(for: word))\b"#, in: text, with: " ")
        }
        text = text.replacingOccurrences(of: ",", with: " , ")
        return Regex.replace(#"\s+"#, in: text, with: " ")
    }

    private static let stopWords: Set<String> = ["and", "or", "but", "then", "no", "with", ",", "in", "at", "under", "over", "less", "more", "than"]

    private func extractIngredientLists(from text: String, into query: inout SearchQuery) {
        let tokens = text.split(separator: " ").map(String.init)
        var index = 0
        var mode: QueryChip.Kind? = nil

        while index < tokens.count {
            let token = tokens[index]
            if token == "no" {
                mode = .exclude
                index += 1
                continue
            }
            if token == "with" {
                mode = .include
                index += 1
                continue
            }
            guard let activeMode = mode else {
                index += 1
                continue
            }

            // Collect a phrase up to the next stop word.
            var phrase: [String] = []
            while index < tokens.count, !Self.stopWords.contains(tokens[index]) {
                phrase.append(tokens[index])
                index += 1
            }
            if !phrase.isEmpty {
                let term = taxonomy.canonicalName(for: phrase.joined(separator: " "))
                add(term, as: activeMode, to: &query)
            }

            // "no dairy or nuts": keep the mode only if the next phrase is a
            // known ingredient; otherwise the list has ended.
            if index < tokens.count, ["and", "or", ","].contains(tokens[index]) {
                index += 1
                let lookahead = tokens[index...].prefix { !Self.stopWords.contains($0) }
                let candidate = taxonomy.canonicalName(for: lookahead.joined(separator: " "))
                if lookahead.isEmpty || taxonomy.parents[candidate] == nil && taxonomy.aliases[candidate] == nil {
                    mode = nil
                }
            } else {
                mode = nil
            }
        }
    }

    private func add(_ term: String, as kind: QueryChip.Kind, to query: inout SearchQuery) {
        guard !term.isEmpty else { return }
        switch kind {
        case .exclude where !query.excludeIngredients.contains(term):
            query.excludeIngredients.append(term)
        case .include where !query.includeIngredients.contains(term):
            query.includeIngredients.append(term)
        default:
            break
        }
    }
}
