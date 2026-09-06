import Foundation
import Observation
import ProportionCore

/// Composition root. One instance lives for the app's lifetime and is
/// injected through the SwiftUI environment. Everything model-backed is
/// optional and gated on both a configured key and the user's privacy
/// setting, so the app is fully functional with neither.
@MainActor
@Observable
final class AppServices {
    let settings = SettingsStore()
    let secrets: Secrets
    let taxonomy = IngredientTaxonomy.standard
    let lineParser = IngredientLineParser()
    let searchEngine = SearchEngine()
    let pendingImports = PendingImportsController()

    private let claudeClient: ClaudeClient?
    private let usdaSource: USDAFoodDataClient?

    init() {
        // Work from a local so no closure touches `self` before every stored
        // property is initialised.
        let loaded = Secrets.load()
        secrets = loaded
        claudeClient = loaded.anthropicAPIKey.map { ClaudeClient(apiKey: $0, model: loaded.claudeModel) }
        usdaSource = loaded.usdaAPIKey.map { USDAFoodDataClient(apiKey: $0) }
    }

    /// Whether model-backed features are both configured and permitted.
    var modelEnabled: Bool {
        claudeClient != nil && settings.useModelForParsing
    }

    var hasModelKey: Bool { claudeClient != nil }
    var hasNutritionKey: Bool { usdaSource != nil }

    var formatter: QuantityFormatter { settings.formatter }

    /// Rebuilt on each access so the current privacy setting is baked in.
    var importer: RecipeImporter {
        let allowed = settings.useModelForParsing
        var importer = RecipeImporter()
        importer.claude = claudeClient.map { ClaudeRecipeParser(client: $0) }
        importer.allowsModel = { allowed }
        return importer
    }

    var queryInterpreter: FallbackQueryInterpreter {
        let primary: (any QueryInterpreter)? = modelEnabled ? claudeClient.map { ClaudeQueryInterpreter(client: $0) } : nil
        return FallbackQueryInterpreter(primary: primary, fallback: KeywordQueryInterpreter(taxonomy: taxonomy))
    }

    /// Nil when there is no USDA key: nutrition then stays whatever the
    /// source (JSON-LD) provided, honestly labelled.
    var nutritionCalculator: NutritionCalculator? {
        guard let usdaSource else { return nil }
        let estimator: (any NutritionEstimator)? = modelEnabled ? claudeClient.map { ClaudeNutritionEstimator(client: $0) } : nil
        return NutritionCalculator(source: usdaSource, estimator: estimator, gramEstimator: GramEstimator(taxonomy: taxonomy), taxonomy: taxonomy)
    }

    // MARK: Library helpers

    /// Runs nutrition lookup for a recipe if possible; returns the recipe
    /// updated with totals and confidence, or unchanged when lookup isn't
    /// configured.
    func priceNutrition(for recipe: Recipe) async -> Recipe {
        guard let calculator = nutritionCalculator else { return recipe }
        let report = await calculator.report(for: recipe)
        guard report.confidence != .unknown else { return recipe }
        return calculator.apply(report, to: recipe)
    }
}
