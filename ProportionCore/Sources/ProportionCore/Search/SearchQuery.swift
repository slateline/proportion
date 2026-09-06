import Foundation

/// The structured form of a search. This is the *only* thing the model
/// produces from a chat message; matching against the library is done
/// locally by `SearchEngine`. Macro limits are per serving.
public struct SearchQuery: Hashable, Codable, Sendable {
    /// Free keywords matched against titles and ingredient names.
    public var text: String?
    public var includeIngredients: [String]
    public var excludeIngredients: [String]
    public var minProtein: Double?
    public var maxProtein: Double?
    public var minCarbs: Double?
    public var maxCarbs: Double?
    public var minFat: Double?
    public var maxFat: Double?
    public var maxCalories: Double?
    public var maxMinutes: Int?
    public var tags: [String]
    public var mealType: String?

    public init(
        text: String? = nil,
        includeIngredients: [String] = [],
        excludeIngredients: [String] = [],
        minProtein: Double? = nil,
        maxProtein: Double? = nil,
        minCarbs: Double? = nil,
        maxCarbs: Double? = nil,
        minFat: Double? = nil,
        maxFat: Double? = nil,
        maxCalories: Double? = nil,
        maxMinutes: Int? = nil,
        tags: [String] = [],
        mealType: String? = nil
    ) {
        self.text = text
        self.includeIngredients = includeIngredients
        self.excludeIngredients = excludeIngredients
        self.minProtein = minProtein
        self.maxProtein = maxProtein
        self.minCarbs = minCarbs
        self.maxCarbs = maxCarbs
        self.minFat = minFat
        self.maxFat = maxFat
        self.maxCalories = maxCalories
        self.maxMinutes = maxMinutes
        self.tags = tags
        self.mealType = mealType
    }

    public var isEmpty: Bool { chips.isEmpty }

    public var hasMacroConstraint: Bool {
        minProtein != nil || maxProtein != nil || minCarbs != nil || maxCarbs != nil
            || minFat != nil || maxFat != nil || maxCalories != nil
    }

    // MARK: Refinement

    /// Follow-up messages mutate the query rather than replacing it:
    /// "actually no chicken either" adds one exclusion and keeps the rest.
    /// Scalars in the refinement override; lists are unioned.
    public mutating func merge(_ refinement: SearchQuery) {
        if let t = refinement.text { text = t }
        for item in refinement.includeIngredients where !includeIngredients.contains(item) {
            includeIngredients.append(item)
        }
        for item in refinement.excludeIngredients where !excludeIngredients.contains(item) {
            excludeIngredients.append(item)
        }
        // Newly excluded things should no longer be required.
        includeIngredients.removeAll { excludeIngredients.contains($0) && refinement.excludeIngredients.contains($0) }
        if let v = refinement.minProtein { minProtein = v }
        if let v = refinement.maxProtein { maxProtein = v }
        if let v = refinement.minCarbs { minCarbs = v }
        if let v = refinement.maxCarbs { maxCarbs = v }
        if let v = refinement.minFat { minFat = v }
        if let v = refinement.maxFat { maxFat = v }
        if let v = refinement.maxCalories { maxCalories = v }
        if let v = refinement.maxMinutes { maxMinutes = v }
        for tag in refinement.tags where !tags.contains(tag) { tags.append(tag) }
        if let m = refinement.mealType { mealType = m }
    }

    public func merged(with refinement: SearchQuery) -> SearchQuery {
        var copy = self
        copy.merge(refinement)
        return copy
    }

    // MARK: Chips

    /// The query rendered as editable chips so the user can see exactly how
    /// their words were interpreted and correct any of it.
    public var chips: [QueryChip] {
        var result: [QueryChip] = []
        if let text, !text.isEmpty {
            result.append(QueryChip(kind: .text, label: "“\(text)”", value: text))
        }
        for item in includeIngredients {
            result.append(QueryChip(kind: .include, label: "with: \(item)", value: item))
        }
        for item in excludeIngredients {
            result.append(QueryChip(kind: .exclude, label: "excludes: \(item)", value: item))
        }
        if let label = Self.rangeLabel("protein", minProtein, maxProtein) {
            result.append(QueryChip(kind: .protein, label: label, value: label))
        }
        if let label = Self.rangeLabel("carbs", minCarbs, maxCarbs) {
            result.append(QueryChip(kind: .carbs, label: label, value: label))
        }
        if let label = Self.rangeLabel("fat", minFat, maxFat) {
            result.append(QueryChip(kind: .fat, label: label, value: label))
        }
        if let maxCalories {
            let label = "≤ \(Self.format(maxCalories)) kcal"
            result.append(QueryChip(kind: .calories, label: label, value: label))
        }
        if let maxMinutes {
            result.append(QueryChip(kind: .time, label: "≤ \(maxMinutes) min", value: "\(maxMinutes)"))
        }
        if let mealType, !mealType.isEmpty {
            result.append(QueryChip(kind: .mealType, label: mealType, value: mealType))
        }
        for tag in tags {
            result.append(QueryChip(kind: .tag, label: "#\(tag)", value: tag))
        }
        return result
    }

    /// The query with one chip's constraint removed.
    public func removing(_ chip: QueryChip) -> SearchQuery {
        var copy = self
        switch chip.kind {
        case .text: copy.text = nil
        case .include: copy.includeIngredients.removeAll { $0 == chip.value }
        case .exclude: copy.excludeIngredients.removeAll { $0 == chip.value }
        case .protein: copy.minProtein = nil; copy.maxProtein = nil
        case .carbs: copy.minCarbs = nil; copy.maxCarbs = nil
        case .fat: copy.minFat = nil; copy.maxFat = nil
        case .calories: copy.maxCalories = nil
        case .time: copy.maxMinutes = nil
        case .mealType: copy.mealType = nil
        case .tag: copy.tags.removeAll { $0 == chip.value }
        case .profile: break // locked; lives in the dietary profile, not the query
        }
        return copy
    }

    static func rangeLabel(_ name: String, _ minimum: Double?, _ maximum: Double?) -> String? {
        switch (minimum, maximum) {
        case (nil, nil): return nil
        case let (lo?, nil): return "\(name) ≥ \(format(lo))g"
        case let (nil, hi?): return "\(name) ≤ \(format(hi))g"
        case let (lo?, hi?): return "\(name) \(format(lo))–\(format(hi))g"
        }
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

public struct QueryChip: Hashable, Identifiable, Sendable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case text, include, exclude, protein, carbs, fat, calories, time, mealType, tag
        /// A persistent exclusion from the dietary profile — visible, not clearable here.
        case profile
    }

    public let kind: Kind
    public let label: String
    public let value: String
    public var isLocked: Bool

    public init(kind: Kind, label: String, value: String, isLocked: Bool = false) {
        self.kind = kind
        self.label = label
        self.value = value
        self.isLocked = isLocked
    }

    public var id: String { "\(kind.rawValue):\(value)" }
}
