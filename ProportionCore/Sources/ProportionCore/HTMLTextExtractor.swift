import Foundation

/// Reduces a web page to readable lines for the text parser when it has no
/// JSON-LD recipe. Deliberately simple: strip the non-content elements,
/// turn block boundaries into newlines, drop the tags, decode entities.
public struct HTMLTextExtractor: Sendable {
    public struct Result: Hashable, Sendable {
        public var title: String?
        public var text: String
    }

    public init() {}

    public func extract(from html: String) -> Result {
        let dotall: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

        let title = Regex.firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html, options: dotall)
            .map { Self.decodeEntities(Self.collapse($0[1])) }
            .flatMap { $0.isEmpty ? nil : $0 }

        var text = html
        for element in ["script", "style", "noscript", "svg", "head", "nav", "footer", "form"] {
            text = Regex.replace(#"<\#(element)\b[^>]*>.*?</\#(element)\s*>"#, in: text, with: " ", options: dotall)
        }
        text = Regex.replace(#"<!--.*?-->"#, in: text, with: " ", options: dotall)
        text = Regex.replace(#"<\s*/?\s*(p|div|br|li|ul|ol|h[1-6]|tr|td|th|section|article|header|blockquote|table|figcaption|dd|dt)\b[^>]*>"#, in: text, with: "\n")
        text = Regex.replace(#"<[^>]+>"#, in: text, with: " ", options: dotall)
        text = Self.decodeEntities(text)

        let lines = text.components(separatedBy: .newlines)
            .map(Self.collapse)
            .filter { !$0.isEmpty }
        return Result(title: title, text: lines.joined(separator: "\n"))
    }

    static func collapse(_ s: String) -> String {
        Regex.replace(#"[\s ]+"#, in: s, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        out = Regex.replace(#"&#x([0-9a-f]+);"#, in: out, with: "") { hex in
            UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
        }
        out = Regex.replace(#"&#(\d+);"#, in: out, with: "") { dec in
            UInt32(dec).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
        }
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&apos;", "'"), ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"),
            ("&frac12;", "½"), ("&frac14;", "¼"), ("&frac34;", "¾"), ("&deg;", "°"),
            ("&amp;", "&"),
        ]
        for (entity, char) in named {
            out = out.replacingOccurrences(of: entity, with: char, options: .caseInsensitive)
        }
        return out
    }
}
