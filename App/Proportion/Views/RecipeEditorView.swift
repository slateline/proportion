import SwiftUI
import SwiftData
import ProportionCore

/// The one editing surface: parse review for captured drafts, manual entry
/// for new recipes, and editing for saved ones. Every ingredient line shows
/// how it was understood next to what was typed, and nothing is saved until
/// the user taps Save.
struct RecipeEditorView: View {
    enum Mode {
        case review(RecipeDraft)
        case blank
        case edit(StoredRecipe)
    }

    let mode: Mode
    var onSaved: ((StoredRecipe) -> Void)? = nil

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var servings = 4
    @State private var servingsAssumed = false
    @State private var prepMinutes = ""
    @State private var cookMinutes = ""
    @State private var attribution = ""
    @State private var sourceURL: URL?
    @State private var imageURL: URL?
    @State private var imageData: Data?
    @State private var tags = ""
    @State private var lines: [EditableLine] = []
    @State private var steps: [EditableStep] = []
    @State private var warnings: [String] = []
    @State private var parseConfidence: Double?
    @State private var perServingMacros: Macros?
    @State private var nutritionConfidence: NutritionConfidence = .unknown
    @State private var saving = false
    @State private var loaded = false

    struct EditableLine: Identifiable {
        let id = UUID()
        var text: String
        var parsed: Ingredient
        var isUnparsed: Bool { parsed.quantity == nil && parsed.descriptor == nil }
    }

    struct EditableStep: Identifiable {
        let id = UUID()
        var text: String
    }

    var body: some View {
        Form {
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
            }

            Section("Recipe") {
                TextField("Title", text: $title)
                    .font(.headline)
                HStack {
                    Stepper("Serves \(servings)", value: $servings, in: ScalingEngine.servingRange)
                    if servingsAssumed {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Serving count was assumed")
                    }
                }
                HStack {
                    TextField("Prep (min)", text: $prepMinutes).keyboardType(.numberPad)
                    Divider()
                    TextField("Cook (min)", text: $cookMinutes).keyboardType(.numberPad)
                }
                TextField("Source", text: $attribution)
                TextField("Tags, comma separated", text: $tags)
                    .textInputAutocapitalization(.never)
            }

            Section {
                ForEach($lines) { $line in
                    IngredientLineEditor(line: $line, formatter: services.formatter, reparse: reparse)
                }
                .onDelete { lines.remove(atOffsets: $0) }
                .onMove { lines.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    lines.append(EditableLine(text: "", parsed: Ingredient(name: "")))
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    let unparsed = lines.filter(\.isUnparsed).count
                    if unparsed > 0 {
                        Text("\(unparsed) without amount")
                            .foregroundStyle(.orange)
                            .textCase(nil)
                    }
                }
            } footer: {
                Text("Lines highlighted in orange couldn't be given a quantity. Edit the text and it will be read again.")
            }

            Section("Steps") {
                ForEach($steps) { $step in
                    TextField("Step", text: $step.text, axis: .vertical)
                        .lineLimit(1...6)
                }
                .onDelete { steps.remove(atOffsets: $0) }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    steps.append(EditableStep(text: ""))
                } label: {
                    Label("Add step", systemImage: "plus")
                }
            }

            if let perServingMacros {
                Section("Nutrition from source (per serving)") {
                    MacroLegend(macros: perServingMacros)
                    ConfidenceBadge(confidence: nutritionConfidence)
                }
            }

            if let parseConfidence {
                Section {
                    LabeledContent("Parse confidence", value: parseConfidence.formatted(.percent.precision(.fractionLength(0))))
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("editor-cancel")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .onAppear(perform: load)
        .interactiveDismissDisabled(saving)
    }

    /// Review mode lives inside ImportFlowView, which has its own Cancel.
    private var showsCancel: Bool {
        if case .review = mode { return false }
        return true
    }

    private var navigationTitle: String {
        switch mode {
        case .review: return "Review recipe"
        case .blank: return "New recipe"
        case .edit: return "Edit recipe"
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && lines.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: Loading

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .review(let draft):
            title = draft.title
            if let s = draft.servings, s >= 1 {
                servings = s
            } else {
                servings = services.settings.defaultServings
                servingsAssumed = true
            }
            prepMinutes = draft.prepMinutes.map(String.init) ?? ""
            cookMinutes = draft.cookMinutes.map(String.init) ?? ""
            attribution = draft.sourceAttribution ?? ""
            sourceURL = draft.sourceURL
            imageURL = draft.imageURL
            warnings = draft.warnings
            parseConfidence = draft.parseConfidence
            perServingMacros = draft.perServingMacros
            nutritionConfidence = draft.nutritionConfidence
            if let structured = draft.ingredients {
                // Show the source's own line text where we have it; otherwise
                // render the structured ingredient back into a line.
                lines = structured.enumerated().map { index, ingredient in
                    let original = index < draft.ingredientLines.count ? draft.ingredientLines[index] : ""
                    let text = original.isEmpty
                        ? services.formatter.line(for: ScaledIngredient(ingredient: ingredient, quantity: ingredient.quantity, note: nil))
                        : original
                    return EditableLine(text: text, parsed: ingredient)
                }
            } else {
                lines = draft.ingredientLines.map { EditableLine(text: $0, parsed: services.lineParser.parse($0)) }
            }
            steps = draft.steps.map { EditableStep(text: $0) }
        case .blank:
            servings = services.settings.defaultServings
            lines = [EditableLine(text: "", parsed: Ingredient(name: ""))]
            steps = [EditableStep(text: "")]
        case .edit(let stored):
            guard let recipe = stored.recipe else { return }
            title = recipe.title
            servings = recipe.baseServings
            prepMinutes = recipe.prepMinutes.map(String.init) ?? ""
            cookMinutes = recipe.cookMinutes.map(String.init) ?? ""
            attribution = recipe.sourceAttribution ?? ""
            sourceURL = recipe.sourceURL
            imageData = stored.imageData
            tags = recipe.tags.sorted().joined(separator: ", ")
            lines = recipe.ingredients.map { ingredient in
                EditableLine(text: services.formatter.line(for: ScaledIngredient(ingredient: ingredient, quantity: ingredient.quantity, note: nil)), parsed: ingredient)
            }
            steps = recipe.steps.map { EditableStep(text: $0) }
            perServingMacros = recipe.perServingMacros
            nutritionConfidence = recipe.nutritionConfidence
        }
    }

    private func reparse(_ line: inout EditableLine) {
        let parsed = services.lineParser.parse(line.text)
        line.parsed = services.taxonomy.tagged(parsed)
    }

    // MARK: Saving

    private func save() async {
        saving = true
        defer { saving = false }

        let ingredients = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { services.taxonomy.tagged($0.parsed) }
        let cleanSteps = steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let tagSet = Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })

        var recipe: Recipe
        switch mode {
        case .edit(let stored):
            recipe = stored.recipe ?? Recipe(title: title, baseServings: servings)
        default:
            recipe = Recipe(title: title, baseServings: servings)
        }
        recipe.title = title.trimmingCharacters(in: .whitespaces)
        recipe.baseServings = servings
        recipe.ingredients = ingredients
        recipe.steps = cleanSteps
        recipe.prepMinutes = Int(prepMinutes)
        recipe.cookMinutes = Int(cookMinutes)
        recipe.sourceAttribution = attribution.isEmpty ? nil : attribution
        recipe.sourceURL = sourceURL
        recipe.tags = tagSet
        if case .review = mode {
            recipe.totalMacros = perServingMacros?.scaled(by: Double(servings))
            recipe.nutritionConfidence = perServingMacros == nil ? .unknown : nutritionConfidence
        }

        if imageData == nil, let imageURL {
            imageData = await ImageFetcher.fetch(imageURL)
        }

        let stored: StoredRecipe
        switch mode {
        case .edit(let existing):
            existing.update(from: recipe)
            if let imageData { existing.imageData = imageData }
            stored = existing
        default:
            stored = StoredRecipe(recipe: recipe, imageData: imageData)
            context.insert(stored)
        }
        try? context.save()

        // Nutrition lookup runs after the save so the user isn't kept waiting;
        // the row updates itself when the numbers arrive.
        let appServices = services
        let recipeSnapshot = recipe
        Task { @MainActor in
            let priced = await appServices.priceNutrition(for: recipeSnapshot)
            if priced.totalMacros != recipeSnapshot.totalMacros || priced.nutritionConfidence != recipeSnapshot.nutritionConfidence {
                stored.update(from: priced)
                try? context.save()
            }
        }

        onSaved?(stored)
        if onSaved == nil { dismiss() }
    }
}

private struct IngredientLineEditor: View {
    @Binding var line: RecipeEditorView.EditableLine
    let formatter: QuantityFormatter
    let reparse: (inout RecipeEditorView.EditableLine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("e.g. 2 cups flour, sifted", text: $line.text)
                .onChange(of: line.text) { _, _ in reparse(&line) }
            HStack(spacing: 6) {
                if line.isUnparsed {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                    Text("No amount recognised")
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(formatter.line(for: ScaledIngredient(ingredient: line.parsed, quantity: line.parsed.quantity, note: nil)))
                }
                if !line.parsed.isScalable {
                    Text("· seasoning").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(line.isUnparsed ? .orange : .secondary)
        }
    }
}

enum ImageFetcher {
    static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: data) else { return nil }
        return image.downsizedJPEGData(maxEdge: 1200)
    }
}
