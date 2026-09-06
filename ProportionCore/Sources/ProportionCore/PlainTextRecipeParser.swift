import Foundation

/// Structures a block of recipe text — pasted, OCR'd, or scraped — without
/// any model call. It finds section headers when they exist, otherwise
/// classifies each line by whether it parses as an ingredient, and pulls
/// servings and times out of the boilerplate.
///
/// It runs first on every text path. The model is only consulted when this
/// parser's confidence is low, which keeps the common case instant, offline,
/// and free.
public struct PlainTextRecipeParser: Sendable {
    public var lineParser: IngredientLineParser

    public init(lineParser: IngredientLineParser = IngredientLineParser()) {
        self.lineParser = lineParser
    }

    /// Nil when the text doesn't look like a recipe at all (fewer than two
    /// ingredient-like lines).
    public func parse(_ text: String, sourceURL: URL? = nil, source: RecipeDraft.Source = .pastedText) -> RecipeDraft? {
        var lines = text.components(separatedBy: .newlines)
            .map(Self.cleanLine)
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var servings: Int?
        var prep: Int?
        var cook: Int?
        lines.removeAll { line in
            if servings == nil, let n = Self.servings(in: line) {
                servings = n
                return Self.isMetadataOnly(line)
            }
            if let (kind, minutes) = Self.time(in: line) {
                switch kind {
                case "prep": prep = prep ?? minutes
                case "cook": cook = cook ?? minutes
                default: break
                }
                return Self.isMetadataOnly(line)
            }
            return false
        }

        let sections = Self.sections(in: lines)
        var title: String?
        var ingredientLines: [String]
        var stepLines: [String]

        if let sections {
            ingredientLines = sections.ingredients
            stepLines = sections.steps
            title = sections.title
        } else {
            var ingredients: [String] = []
            var steps: [String] = []
            var seenIngredient = false
            for (index, line) in lines.enumerated() {
                if Self.looksLikeStep(line) {
                    steps.append(line)
                    continue
                }
                if looksLikeIngredient(line) {
                    ingredients.append(line)
                    seenIngredient = true
                    continue
                }
                if index == 0, title == nil, Self.looksLikeTitle(line) {
                    title = line
                    continue
                }
                if seenIngredient, line.count >= 25 {
                    steps.append(line)
                }
            }
            ingredientLines = ingredients
            stepLines = steps
        }

        guard ingredientLines.count >= 2 else { return nil }

        let steps = stepLines.map(Self.stripStepNumbering).filter { !$0.isEmpty }
        let quantified = ingredientLines.filter { lineParser.parse($0).quantity != nil }.count

        var confidence = min(0.8, 0.2 + 0.1 * Double(quantified))
        if sections != nil { confidence += 0.1 }
        if !steps.isEmpty { confidence += 0.05 }
        confidence = min(confidence, 0.95)

        var warnings: [String] = []
        if steps.isEmpty { warnings.append("No instructions were found in the text.") }

        return RecipeDraft(
            title: title ?? "Untitled recipe",
            sourceURL: sourceURL,
            sourceAttribution: sourceURL?.host,
            servings: servings,
            ingredientLines: ingredientLines,
            steps: steps,
            prepMinutes: prep,
            cookMinutes: cook,
            parseConfidence: confidence,
            source: source,
            warnings: warnings)
    }

    // MARK: Classification

    func looksLikeIngredient(_ line: String) -> Bool {
        guard line.count <= 120 else { return false }
        let parsed = lineParser.parse(line)
        return parsed.quantity != nil || parsed.descriptor != nil
    }

    static func looksLikeStep(_ line: String) -> Bool {
        Regex.firstMatch(#"^(step\s*\d+|\d+[.)])\s+\S"#, in: line) != nil
    }

    static func looksLikeTitle(_ line: String) -> Bool {
        line.count <= 80 && !line.hasSuffix(".") && Regex.firstMatch(#"^\d"#, in: line) == nil
    }

    static func stripStepNumbering(_ line: String) -> String {
        Regex.replace(#"^(step\s*\d+[:.)]?|\d+[.)])\s*"#, in: line, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Strips bullets, checkboxes, and stray whitespace.
    static func cleanLine(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        line = Regex.replace(#"^[\-\*•▢☐□■·◦●o]\s*"#, in: line, with: "")
        return Regex.replace(#"\s+"#, in: line, with: " ")
    }

    // MARK: Sections

    struct Sections {
        var title: String?
        var ingredients: [String]
        var steps: [String]
    }

    private static let ingredientHeader = #"^(ingredients?|what you need|you will need|you'll need)\s*:?$"#
    private static let stepHeader = #"^(directions?|instructions?|method|steps|preparation|how to make.*|procedure)\s*:?$"#
    private static let otherHeader = #"^(notes?|tips?|nutrition(?: facts| information)?|equipment|storage|serving suggestions?)\s*:?$"#

    static func sections(in lines: [String]) -> Sections? {
        var ingredientIndex: Int?
        var stepIndex: Int?
        var headerIndices: [Int] = []
        for (index, line) in lines.enumerated() where line.count <= 40 {
            if Regex.firstMatch(ingredientHeader, in: line) != nil {
                if ingredientIndex == nil { ingredientIndex = index }
                headerIndices.append(index)
            } else if Regex.firstMatch(stepHeader, in: line) != nil {
                if stepIndex == nil { stepIndex = index }
                headerIndices.append(index)
            } else if Regex.firstMatch(otherHeader, in: line) != nil {
                headerIndices.append(index)
            }
        }
        guard let ingredientIndex else { return nil }

        func body(after header: Int) -> [String] {
            let next = headerIndices.filter { $0 > header }.min() ?? lines.count
            return Array(lines[(header + 1)..<next])
        }

        let firstHeader = headerIndices.min() ?? ingredientIndex
        let title = firstHeader > 0 ? lines[0..<firstHeader].first(where: looksLikeTitle) : nil
        return Sections(
            title: title,
            ingredients: body(after: ingredientIndex),
            steps: stepIndex.map(body(after:)) ?? [])
    }

    // MARK: Metadata

    static func servings(in line: String) -> Int? {
        if let groups = Regex.firstMatch(#"\b(?:serves|servings?|yields?|makes)\s*:?\s*(\d+)"#, in: line) {
            return Int(groups[1])
        }
        if let groups = Regex.firstMatch(#"\b(\d+)\s*servings?\b"#, in: line) {
            return Int(groups[1])
        }
        return nil
    }

    /// Returns ("prep" | "cook" | "total", minutes).
    static func time(in line: String) -> (String, Int)? {
        let pattern = #"\b(prep(?:aration)?|cook(?:ing)?|total)\s*time\s*:?\s*(\d+)\s*(h|hr|hrs|hours?|m|min|mins|minutes?)\b(?:\s*(\d+)\s*(m|min|mins|minutes?))?"#
        guard let g = Regex.firstMatch(pattern, in: line), let first = Int(g[2]) else { return nil }
        var minutes = g[3].lowercased().hasPrefix("h") ? first * 60 : first
        if let extra = Int(g[4]) { minutes += extra }
        let kind = g[1].lowercased().hasPrefix("prep") ? "prep" : g[1].lowercased().hasPrefix("cook") ? "cook" : "total"
        return (kind, minutes)
    }

    /// True when the line is *only* metadata ("Serves 4", "Prep time: 10 min")
    /// and should be dropped rather than kept as an ingredient or step.
    static func isMetadataOnly(_ line: String) -> Bool {
        line.count <= 40
    }
}
