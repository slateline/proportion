import Foundation

/// Named bundles of exclusions. Each expands to taxonomy category names so
/// the hierarchy does the work: `nutFree` excludes "nut", which catches
/// almonds, peanuts, pesto, and marzipan.
public enum DietaryPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case vegetarian
    case vegan
    case pescatarian
    case glutenFree
    case dairyFree
    case nutFree
    case eggFree
    case soyFree
    case shellfishFree

    public var title: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .glutenFree: return "Gluten-free"
        case .dairyFree: return "Dairy-free"
        case .nutFree: return "Nut-free"
        case .eggFree: return "Egg-free"
        case .soyFree: return "Soy-free"
        case .shellfishFree: return "Shellfish-free"
        }
    }

    /// The word a user types to mean this preset.
    var keyword: String {
        switch self {
        case .vegetarian: return "vegetarian"
        case .vegan: return "vegan"
        case .pescatarian: return "pescatarian"
        case .glutenFree: return "gluten[- ]free"
        case .dairyFree: return "dairy[- ]free"
        case .nutFree: return "nut[- ]free"
        case .eggFree: return "egg[- ]free"
        case .soyFree: return "soy[- ]free"
        case .shellfishFree: return "shellfish[- ]free"
        }
    }

    public var exclusions: Set<String> {
        switch self {
        case .vegetarian: return ["meat", "fish", "shellfish", "gelatin"]
        case .vegan: return ["meat", "fish", "shellfish", "gelatin", "dairy", "egg", "honey"]
        case .pescatarian: return ["meat"]
        case .glutenFree: return ["gluten"]
        case .dairyFree: return ["dairy"]
        case .nutFree: return ["nut"]
        case .eggFree: return ["egg"]
        case .soyFree: return ["soy"]
        case .shellfishFree: return ["shellfish"]
        }
    }
}

/// The user's standing exclusions — allergies and hard dietary rules. Set
/// once in Settings, applied to every search, shown as locked chips.
///
/// This is a convenience filter over parsed ingredient text. It is never
/// presented as allergen safety, and the UI must never describe results as
/// "safe" or "free from": the filter can't know about cross-contamination,
/// "may contain" labelling, or an ingredient the parser missed.
public struct DietaryProfile: Hashable, Codable, Sendable {
    public var presets: Set<DietaryPreset>
    public var customExclusions: Set<String>

    public init(presets: Set<DietaryPreset> = [], customExclusions: Set<String> = []) {
        self.presets = presets
        self.customExclusions = customExclusions
    }

    public static let empty = DietaryProfile()

    public var isEmpty: Bool { presets.isEmpty && customExclusions.isEmpty }

    /// Every exclusion term in force, presets expanded.
    public var allExclusions: Set<String> {
        presets.reduce(into: customExclusions) { $0.formUnion($1.exclusions) }
    }

    public func violations(in recipe: Recipe, taxonomy: IngredientTaxonomy = .standard) -> [Ingredient] {
        taxonomy.violations(in: recipe, excluding: allExclusions)
    }

    public func allows(_ recipe: Recipe, taxonomy: IngredientTaxonomy = .standard) -> Bool {
        isEmpty || violations(in: recipe, taxonomy: taxonomy).isEmpty
    }

    /// Locked chips for the search screen, one per preset plus each custom term.
    public var chips: [QueryChip] {
        var result = presets.sorted { $0.title < $1.title }.map {
            QueryChip(kind: .profile, label: $0.title, value: $0.rawValue, isLocked: true)
        }
        result += customExclusions.sorted().map {
            QueryChip(kind: .profile, label: "no \($0)", value: $0, isLocked: true)
        }
        return result
    }

    /// Shown wherever the profile is edited. Deliberately avoids the words
    /// "safe" and "free from".
    public static let disclaimer =
        "Your dietary profile hides recipes whose parsed ingredients match these terms. "
        + "It works from ingredient text, which can be incomplete or wrong, and it knows nothing about "
        + "cross-contamination or “may contain” labelling. It is a convenience, not a substitute for "
        + "reading labels or checking with whoever cooked the food."
}
