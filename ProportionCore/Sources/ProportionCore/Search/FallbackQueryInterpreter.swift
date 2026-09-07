import Foundation

/// Tries the model-backed interpreter and, if it is unavailable or fails for
/// any reason — offline, no key, timeout, bad output — falls back to the
/// deterministic keyword interpreter so search is never blocked.
public struct FallbackQueryInterpreter: QueryInterpreter {
    public var primary: (any QueryInterpreter)?
    public var fallback: KeywordQueryInterpreter

    public init(primary: (any QueryInterpreter)?, fallback: KeywordQueryInterpreter = KeywordQueryInterpreter()) {
        self.primary = primary
        self.fallback = fallback
    }

    /// What answered, so the UI can say so and testers can see failures.
    public struct Interpretation: Sendable {
        public enum Source: String, Sendable {
            case model
            case keyword
        }

        public var query: SearchQuery
        public var source: Source
        /// Set when the model was tried and failed; the query then came from the fallback.
        public var modelError: String?
    }

    public func interpret(_ message: String, refining current: SearchQuery?) async throws -> SearchQuery {
        await interpretDetailed(message, refining: current).query
    }

    public func interpretDetailed(_ message: String, refining current: SearchQuery?) async -> Interpretation {
        guard let primary else {
            return Interpretation(query: fallback.parse(message, refining: current), source: .keyword, modelError: nil)
        }
        do {
            let query = try await primary.interpret(message, refining: current)
            return Interpretation(query: query, source: .model, modelError: nil)
        } catch {
            return Interpretation(
                query: fallback.parse(message, refining: current),
                source: .keyword,
                modelError: error.localizedDescription)
        }
    }
}
