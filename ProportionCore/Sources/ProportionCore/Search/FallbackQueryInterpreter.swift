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

    public func interpret(_ message: String, refining current: SearchQuery?) async throws -> SearchQuery {
        if let primary, let query = try? await primary.interpret(message, refining: current) {
            return query
        }
        return fallback.parse(message, refining: current)
    }
}
