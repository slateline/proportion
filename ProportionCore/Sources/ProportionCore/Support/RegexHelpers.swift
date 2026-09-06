import Foundation

/// Thin wrappers over NSRegularExpression so parsing code reads clearly.
/// Patterns are compile-time constants throughout the package, so a failure
/// to compile one is a programmer error and traps.
enum Regex {
    private static let cache = RegexCache()

    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [[String]] {
        let regex = cache.regex(pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { groups(of: $0, in: text) }
    }

    static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [String]? {
        let regex = cache.regex(pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return groups(of: match, in: text)
    }

    static func replace(_ pattern: String, in text: String, with template: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> String {
        let regex = cache.regex(pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    /// Replace each match with the result of `transform(group1)`.
    static func replace(_ pattern: String, in text: String, with _: String, options: NSRegularExpression.Options = [.caseInsensitive], transform: (String) -> String) -> String {
        let regex = cache.regex(pattern, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        // Walk matches back to front so earlier ranges stay valid.
        for match in regex.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range, in: text) else { continue }
            let group = match.numberOfRanges > 1 ? Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? "" : ""
            result.replaceSubrange(whole, with: transform(group))
        }
        return result
    }

    /// Capture groups 0…n; groups that did not participate are empty strings.
    private static func groups(of match: NSTextCheckingResult, in text: String) -> [String] {
        (0..<match.numberOfRanges).map { index in
            guard let r = Range(match.range(at: index), in: text) else { return "" }
            return String(text[r])
        }
    }
}

/// Compiled patterns are reused across calls. Locked because parsing can be
/// invoked from any task.
private final class RegexCache: @unchecked Sendable {
    private var storage: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression {
        let key = "\(options.rawValue):\(pattern)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = storage[key] { return existing }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("Invalid regex pattern: \(pattern)")
        }
        storage[key] = compiled
        return compiled
    }
}
