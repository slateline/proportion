import Foundation

/// Pulls a schema.org `Recipe` out of a web page's JSON-LD.
///
/// Most recipe sites publish this for search engines, and it is far more
/// reliable than any text extraction: ingredients arrive as a clean list,
/// the yield is explicit, durations are ISO 8601, and nutrition is usually
/// attached. When it's present this is the whole parse; the model is only
/// asked to help when it's absent.
public struct JSONLDRecipeExtractor: Sendable {
    public init() {}

    /// The first recipe found in the page, or nil if there is none.
    public func extract(fromHTML html: String, pageURL: URL? = nil) -> RecipeDraft? {
        for block in Self.scriptBlocks(in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            for recipe in Self.findRecipes(in: json) {
                if let draft = Self.draft(from: recipe, pageURL: pageURL) { return draft }
            }
        }
        return nil
    }

    // MARK: Locating the JSON

    static func scriptBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            var body = String(html[r])
            body = body.replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Recipes can sit at the top level, in an array, inside `@graph`, or be
    /// nested in another entity. Walk everything.
    static func findRecipes(in json: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if isRecipe(dict) { found.append(dict) }
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)
        return found
    }

    static func isRecipe(_ dict: [String: Any]) -> Bool {
        types(of: dict).contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame }
    }

    private static func types(of dict: [String: Any]) -> [String] {
        if let single = dict["@type"] as? String { return [single] }
        if let many = dict["@type"] as? [String] { return many }
        return []
    }

    // MARK: Mapping

    static func draft(from recipe: [String: Any], pageURL: URL?) -> RecipeDraft? {
        guard let title = string(recipe["name"]), !title.isEmpty else { return nil }
        let lines = stringList(recipe["recipeIngredient"] ?? recipe["ingredients"])
        guard !lines.isEmpty else { return nil }

        var warnings: [String] = []
        let steps = instructions(from: recipe["recipeInstructions"])
        if steps.isEmpty { warnings.append("No instructions were found on the page.") }

        let servings = yield(from: recipe["recipeYield"])
        let (perServing, confidence) = nutrition(from: recipe["nutrition"])

        let url = string(recipe["url"]).flatMap(URL.init(string:))
            ?? string((recipe["mainEntityOfPage"] as? [String: Any])?["@id"]).flatMap(URL.init(string:))
            ?? pageURL

        return RecipeDraft(
            title: title,
            sourceURL: url,
            sourceAttribution: author(from: recipe["author"]) ?? url?.host,
            imageURL: image(from: recipe["image"]),
            servings: servings,
            ingredientLines: lines,
            steps: steps,
            prepMinutes: minutes(fromISO8601: string(recipe["prepTime"])),
            cookMinutes: minutes(fromISO8601: string(recipe["cookTime"])),
            perServingMacros: perServing,
            nutritionConfidence: confidence,
            parseConfidence: 0.95,
            source: .jsonLD,
            warnings: warnings
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func stringList(_ value: Any?) -> [String] {
        if let s = string(value) { return s.isEmpty ? [] : [s] }
        if let array = value as? [Any] {
            return array.compactMap(string).filter { !$0.isEmpty }
        }
        return []
    }

    /// Strings, arrays of strings, HowToStep objects, and HowToSection groups.
    static func instructions(from value: Any?) -> [String] {
        if let s = string(value) {
            return s.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let dict = value as? [String: Any] {
            if let items = dict["itemListElement"] { return instructions(from: items) }
            if let text = string(dict["text"]) { return [stripHTML(text)] }
            return []
        }
        if let array = value as? [Any] {
            return array.flatMap { instructions(from: $0) }
        }
        return []
    }

    /// "4", "4 servings", "Serves 4", ["4", "4 servings"], or a number.
    static func yield(from value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue > 0 ? n.intValue : nil }
        if let s = value as? String { return firstInteger(in: s) }
        if let array = value as? [Any] {
            for item in array { if let n = yield(from: item) { return n } }
        }
        return nil
    }

    static func firstInteger(in text: String) -> Int? {
        var digits = ""
        for ch in text {
            if ch.isNumber { digits.append(ch) } else if !digits.isEmpty { break }
        }
        guard let n = Int(digits), n > 0 else { return nil }
        return n
    }

    static func firstDouble(in text: String) -> Double? {
        var token = ""
        var seenDigit = false
        for ch in text {
            if ch.isNumber { token.append(ch); seenDigit = true }
            else if (ch == "." || ch == ",") && seenDigit && !token.contains(".") { token.append(".") }
            else if seenDigit { break }
        }
        return Double(token)
    }

    /// ISO 8601 durations: PT30M, PT1H30M, P0DT1H, PT45S.
    static func minutes(fromISO8601 text: String?) -> Int? {
        guard let text, text.uppercased().hasPrefix("P") else { return nil }
        var total = 0.0
        var number = ""
        var inTime = false
        for ch in text.uppercased().dropFirst() {
            if ch.isNumber || ch == "." {
                number.append(ch)
                continue
            }
            if ch == "T" { inTime = true; continue }
            let value = Double(number) ?? 0
            number = ""
            switch ch {
            case "D": total += value * 24 * 60
            case "H": total += value * 60
            case "M": total += inTime ? value : value * 30 * 24 * 60
            case "S": total += value / 60
            default: break
            }
        }
        let rounded = Int(total.rounded())
        return rounded > 0 ? rounded : nil
    }

    static func nutrition(from value: Any?) -> (Macros?, NutritionConfidence) {
        guard let dict = value as? [String: Any] else { return (nil, .unknown) }
        let protein = string(dict["proteinContent"]).flatMap(firstDouble)
        let fat = string(dict["fatContent"]).flatMap(firstDouble)
        let carbs = string(dict["carbohydrateContent"]).flatMap(firstDouble)
        guard protein != nil || fat != nil || carbs != nil else { return (nil, .unknown) }
        // Site-published nutrition is unverified by us; mark it as an estimate
        // so the recipe shows the honest confidence state.
        return (Macros(protein: protein ?? 0, fat: fat ?? 0, carbs: carbs ?? 0), .estimated)
    }

    private static func author(from value: Any?) -> String? {
        if let s = string(value) { return s }
        if let dict = value as? [String: Any] { return string(dict["name"]) }
        if let array = value as? [Any], let first = array.first { return author(from: first) }
        return nil
    }

    private static func image(from value: Any?) -> URL? {
        if let s = string(value) { return URL(string: s) }
        if let dict = value as? [String: Any] { return string(dict["url"]).flatMap(URL.init(string:)) }
        if let array = value as? [Any], let first = array.first { return image(from: first) }
        return nil
    }

    static func stripHTML(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
