import Foundation

/// API keys, injected at build time from Config/Secrets.xcconfig via
/// Info.plist. Never hardcoded; an empty or placeholder value reads as nil
/// so the app degrades to its deterministic parsers instead of failing.
struct Secrets: Sendable {
    var anthropicAPIKey: String?
    var usdaAPIKey: String?
    var claudeModel: String

    static func load(from bundle: Bundle = .main) -> Secrets {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("$(") || trimmed.hasSuffix("...") { return nil }
            return trimmed
        }
        return Secrets(
            anthropicAPIKey: value("ANTHROPIC_API_KEY"),
            usdaAPIKey: value("USDA_API_KEY"),
            claudeModel: value("CLAUDE_MODEL") ?? "claude-opus-5")
    }
}
