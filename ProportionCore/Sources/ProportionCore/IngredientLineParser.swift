import Foundation

/// Deterministic parser for a single ingredient line.
///
/// "2 cups all-purpose flour, sifted" → 2 cup / all-purpose flour / sifted.
///
/// This handles the overwhelmingly common shapes without a model call, which
/// keeps parsing instant, offline, and exact — quantities come out as
/// rationals, not floats. Anything it cannot confidently structure is left
/// with a nil quantity and the whole text as the name, so nothing is lost and
/// the LLM path or the user can finish the job.
public struct IngredientLineParser: Sendable {
    public init() {}

    public func parse(_ line: String) -> Ingredient {
        var text = Self.replaceVulgarFractions(line)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // "(14 oz)" and similar asides become preparation notes.
        var parentheticals: [String] = []
        text = Self.extractParentheticals(from: text, into: &parentheticals)

        // "a pinch of nutmeg", "dash of hot sauce" — checked before number
        // parsing because "a" would otherwise be read as the number 1.
        if let (name, descriptor) = Self.matchPrefixDescriptor(text) {
            return descriptorIngredient(name: name, descriptor: descriptor, notes: parentheticals)
        }

        var (amount, rest) = Self.parseLeadingNumber(text)

        // "salt to taste", "parsley, for garnish" — only when there is no
        // quantity; "2 tbsp parsley, for garnish" keeps its amount and the
        // phrase lands in preparation via the comma split below.
        if amount == nil, let (name, descriptor) = Self.matchSuffixDescriptor(text) {
            return descriptorIngredient(name: name, descriptor: descriptor, notes: parentheticals)
        }

        var unit: MeasurementUnit = .unitless
        if amount != nil {
            let (parsedUnit, afterUnit) = Self.parseUnit(rest)
            if let parsedUnit { unit = parsedUnit }
            rest = afterUnit
            rest = Self.dropLeadingArticle(rest)
        }

        // First comma splits name from preparation.
        var name = rest
        var preparation: String? = nil
        if let comma = rest.firstIndex(of: ",") {
            name = String(rest[..<comma])
            preparation = String(rest[rest.index(after: comma)...])
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        preparation = preparation?.trimmingCharacters(in: .whitespacesAndNewlines)

        var notes: [String] = []
        if let preparation, !preparation.isEmpty { notes.append(preparation) }
        notes.append(contentsOf: parentheticals)

        // A line with no name at all is unparseable; keep the original text.
        if name.isEmpty {
            amount = nil
            name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            notes = []
        }

        var ingredient = Ingredient(name: name)
        if let amount {
            ingredient.quantity = Quantity(amount, unit)
        }
        ingredient.preparation = Self.joinNotes(notes)
        ingredient.isScalable = !Self.isNonLinear(name)
        return ingredient
    }

    private func descriptorIngredient(name: String, descriptor: String, notes: [String]) -> Ingredient {
        var ingredient = Ingredient(name: name, descriptor: descriptor)
        ingredient.isScalable = !Self.isNonLinear(name)
        ingredient.preparation = Self.joinNotes(notes)
        return ingredient
    }

    /// "of flour" → "flour", "a lemon" → "lemon".
    private static func dropLeadingArticle(_ text: String) -> String {
        let lower = text.lowercased()
        for article in ["of ", "a ", "an "] where lower.hasPrefix(article) {
            return String(text.dropFirst(article.count))
        }
        return text
    }

    public func parse(lines: [String]) -> [Ingredient] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(parse)
    }

    // MARK: Numbers

    /// Accepts "2", "1.5", "1/2", "1 1/2", "2-3" (takes the lower bound) and
    /// leading words like "one", "half". Returns the number and the remainder.
    static func parseLeadingNumber(_ text: String) -> (Rational?, String) {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = tokens.first else { return (nil, text) }

        // Words
        if let word = numberWords[first.lowercased()] {
            tokens.removeFirst()
            return (word, tokens.joined(separator: " "))
        }

        // Ranges: "2-3", "2 - 3", "2 to 3"
        var head = first
        if let dash = head.firstIndex(where: { $0 == "-" || $0 == "–" }),
           dash != head.startIndex, let lower = rational(from: String(head[..<dash])) {
            tokens.removeFirst()
            return (lower, tokens.joined(separator: " "))
        }

        // Numbers glued to a unit: "500g", "2tbsp"
        if let split = splitGluedUnit(head) {
            head = split.number
            tokens[0] = split.number
            tokens.insert(split.unit, at: 1)
        }

        guard var amount = rational(from: head) else { return (nil, text) }
        tokens.removeFirst()

        // Mixed number: "1 1/2"
        if let next = tokens.first, next.contains("/"), let fraction = rational(from: next), amount.isInteger {
            amount = amount + fraction
            tokens.removeFirst()
        }

        // "2 - 3" / "2 to 3"
        if tokens.count >= 2, tokens[0] == "-" || tokens[0] == "–" || tokens[0].lowercased() == "to",
           rational(from: tokens[1]) != nil {
            tokens.removeFirst(2)
        }

        return (amount, tokens.joined(separator: " "))
    }

    static func rational(from token: String) -> Rational? {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        if cleaned.isEmpty { return nil }
        if let slash = cleaned.firstIndex(of: "/") {
            guard let n = Int(cleaned[..<slash]), let d = Int(cleaned[cleaned.index(after: slash)...]), d != 0 else { return nil }
            return Rational(n, d)
        }
        if let whole = Int(cleaned) { return Rational(whole) }
        if let decimal = Double(cleaned), decimal.isFinite {
            return Rational(approximating: decimal, maxDenominator: 1000)
        }
        return nil
    }

    private static func splitGluedUnit(_ token: String) -> (number: String, unit: String)? {
        var index = token.startIndex
        while index < token.endIndex, token[index].isNumber || token[index] == "." || token[index] == "/" {
            index = token.index(after: index)
        }
        guard index != token.startIndex, index != token.endIndex else { return nil }
        let unit = String(token[index...])
        guard unitAliases[unit.lowercased()] != nil else { return nil }
        return (String(token[..<index]), unit)
    }

    private static let numberWords: [String: Rational] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "dozen": 12,
        "half": Rational(1, 2), "quarter": Rational(1, 4),
    ]

    // MARK: Units

    static func parseUnit(_ text: String) -> (MeasurementUnit?, String) {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = tokens.first else { return (nil, text) }

        // Two-word units first: "fl oz", "fluid ounces"
        if tokens.count >= 2 {
            let pair = (first + " " + tokens[1]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if let unit = unitAliases[pair] {
                tokens.removeFirst(2)
                return (unit, tokens.joined(separator: " "))
            }
        }

        // Single letters are case-sensitive by convention: T = tablespoon, t = teaspoon.
        let bare = first.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        if bare == "T" {
            tokens.removeFirst()
            return (.tablespoon, tokens.joined(separator: " "))
        }
        if bare == "t" {
            tokens.removeFirst()
            return (.teaspoon, tokens.joined(separator: " "))
        }

        let single = bare.lowercased()
        if let unit = unitAliases[single] {
            tokens.removeFirst()
            return (unit, tokens.joined(separator: " "))
        }
        return (nil, text)
    }

    static let unitAliases: [String: MeasurementUnit] = [
        "tsp": .teaspoon, "tsps": .teaspoon, "teaspoon": .teaspoon, "teaspoons": .teaspoon,
        "tbsp": .tablespoon, "tbsps": .tablespoon, "tbs": .tablespoon, "tablespoon": .tablespoon,
        "tablespoons": .tablespoon,
        "cup": .cup, "cups": .cup, "c": .cup,
        "fl oz": .fluidOunce, "fluid ounce": .fluidOunce, "fluid ounces": .fluidOunce, "floz": .fluidOunce,
        "ml": .milliliter, "milliliter": .milliliter, "milliliters": .milliliter,
        "millilitre": .milliliter, "millilitres": .milliliter,
        "l": .liter, "liter": .liter, "liters": .liter, "litre": .liter, "litres": .liter,
        "g": .gram, "gram": .gram, "grams": .gram, "gr": .gram,
        "kg": .kilogram, "kilogram": .kilogram, "kilograms": .kilogram,
        "oz": .ounce, "ounce": .ounce, "ounces": .ounce,
        "lb": .pound, "lbs": .pound, "pound": .pound, "pounds": .pound,
        "clove": .clove, "cloves": .clove,
        "slice": .slice, "slices": .slice,
        "can": .can, "cans": .can, "tin": .can, "tins": .can,
        "stick": .stick, "sticks": .stick,
        "bunch": .bunch, "bunches": .bunch,
        "piece": .piece, "pieces": .piece,
    ]

    // MARK: Descriptors

    private static let descriptorPunctuation = CharacterSet(charactersIn: ",;:").union(.whitespaces)

    /// "salt to taste", "parsley, for garnish".
    static func matchSuffixDescriptor(_ text: String) -> (name: String, descriptor: String)? {
        let lower = text.lowercased()
        for suffix in ["to taste", "as needed", "for serving", "for garnish", "optional"] where lower.hasSuffix(suffix) {
            let name = String(text.dropLast(suffix.count)).trimmingCharacters(in: descriptorPunctuation)
            if !name.isEmpty { return (name, suffix) }
        }
        return nil
    }

    /// "a pinch of nutmeg", "dash of hot sauce".
    static func matchPrefixDescriptor(_ text: String) -> (name: String, descriptor: String)? {
        let lower = text.lowercased()
        for word in ["pinch", "dash", "splash", "handful", "drizzle", "squeeze", "knob"] {
            for prefix in ["a \(word) of ", "\(word) of "] where lower.hasPrefix(prefix) {
                let name = String(text.dropFirst(prefix.count)).trimmingCharacters(in: descriptorPunctuation)
                if !name.isEmpty { return (name, "a \(word)") }
            }
        }
        return nil
    }

    // MARK: Non-linear items

    /// Ingredients whose amounts don't scale cleanly — leavening and strong
    /// seasonings. They still scale; the UI shows a note.
    static func isNonLinear(_ name: String) -> Bool {
        let lower = " " + IngredientTaxonomy.normalise(name) + " "
        return nonLinearTerms.contains { lower.contains(" \($0) ") }
    }

    private static let nonLinearTerms: [String] = [
        "baking soda", "baking powder", "yeast", "salt", "black pepper", "white pepper",
        "ground pepper", "peppercorns", "cayenne", "chili flakes", "red pepper flakes",
        "chili powder", "cinnamon", "nutmeg", "cumin", "paprika", "oregano", "thyme",
        "rosemary", "cloves", "allspice", "cardamom", "turmeric", "ground ginger",
        "garlic powder", "onion powder", "vanilla", "vanilla extract", "almond extract",
        "hot sauce", "msg",
    ]

    // MARK: Text helpers

    private static let vulgarFractions: [Character: String] = [
        "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
        "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8", "⅙": "1/6", "⅚": "5/6",
    ]

    static func replaceVulgarFractions(_ text: String) -> String {
        var out = ""
        var previous: Character? = nil
        for ch in text {
            if let fraction = vulgarFractions[ch] {
                // "1½" → "1 1/2"
                if let p = previous, p.isNumber { out.append(" ") }
                out.append(fraction)
            } else {
                out.append(ch)
            }
            previous = ch
        }
        return out
    }

    static func extractParentheticals(from text: String, into notes: inout [String]) -> String {
        var result = ""
        var depth = 0
        var current = ""
        for ch in text {
            if ch == "(" {
                depth += 1
                continue
            }
            if ch == ")" && depth > 0 {
                depth -= 1
                if depth == 0 {
                    let note = current.trimmingCharacters(in: .whitespaces)
                    if !note.isEmpty { notes.append(note) }
                    current = ""
                }
                continue
            }
            if depth > 0 { current.append(ch) } else { result.append(ch) }
        }
        return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func joinNotes(_ notes: [String]) -> String? {
        let cleaned = notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }
}
