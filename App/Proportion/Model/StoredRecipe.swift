import Foundation
import SwiftData
import ProportionCore

/// The persisted form of a recipe.
///
/// `ProportionCore.Recipe` is a value type with nested structs and rationals;
/// rather than mirror all of that as SwiftData relationships, the whole
/// recipe is stored as one JSON blob and a handful of fields are
/// denormalised for sorting and predicates. This also keeps the schema
/// CloudKit-compatible: every property has a default and nothing is unique.
@Model
final class StoredRecipe {
    var recipeID: UUID = UUID()
    var title: String = ""
    var payload: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Denormalised for sort descriptors and quick display.
    var proteinPerServing: Double = 0
    var carbsPerServing: Double = 0
    var fatPerServing: Double = 0
    var caloriesPerServing: Double = 0
    var totalMinutes: Int = 0
    var baseServings: Int = 1
    var hasNutrition: Bool = false
    var tagsText: String = ""

    /// Hero image, downsized on import. Optional so text-only recipes cost nothing.
    @Attribute(.externalStorage) var imageData: Data? = nil

    init(recipe: Recipe, imageData: Data? = nil) {
        self.imageData = imageData
        update(from: recipe)
        self.createdAt = recipe.createdAt
    }

    /// Decodes the stored recipe. Nil only if the payload is corrupt, which
    /// the library view treats as a row to show with a repair action.
    var recipe: Recipe? {
        try? JSONDecoder().decode(Recipe.self, from: payload)
    }

    func update(from recipe: Recipe) {
        recipeID = recipe.id
        title = recipe.title
        payload = (try? JSONEncoder().encode(recipe)) ?? Data()
        updatedAt = Date()
        baseServings = recipe.baseServings
        totalMinutes = recipe.totalMinutes ?? 0
        tagsText = recipe.tags.sorted().joined(separator: " ")
        if let per = recipe.perServingMacros {
            proteinPerServing = per.protein
            carbsPerServing = per.carbs
            fatPerServing = per.fat
            caloriesPerServing = per.calories
            hasNutrition = true
        } else {
            proteinPerServing = 0
            carbsPerServing = 0
            fatPerServing = 0
            caloriesPerServing = 0
            hasNutrition = false
        }
    }
}

extension StoredRecipe {
    enum SortOrder: String, CaseIterable, Identifiable {
        case newest, title, protein, quickest
        var id: String { rawValue }

        var title: String {
            switch self {
            case .newest: return "Newest"
            case .title: return "Title"
            case .protein: return "Most protein"
            case .quickest: return "Quickest"
            }
        }

        var descriptors: [SortDescriptor<StoredRecipe>] {
            switch self {
            case .newest: return [SortDescriptor(\.createdAt, order: .reverse)]
            case .title: return [SortDescriptor(\.title)]
            case .protein: return [SortDescriptor(\.proteinPerServing, order: .reverse)]
            case .quickest: return [SortDescriptor(\.totalMinutes)]
            }
        }
    }
}
