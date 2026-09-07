import SwiftUI
import SwiftData
import ProportionCore

struct RecipeDetailView: View {
    let stored: StoredRecipe

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var servings: Int = 4
    @State private var proteinTarget = ""
    @State private var proteinScaled: ScaledRecipe?
    @State private var proteinError: String?
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var exportURL: URL?

    var body: some View {
        if let recipe = stored.recipe {
            content(for: recipe)
        } else {
            ContentUnavailableView("This recipe couldn't be read", systemImage: "exclamationmark.triangle")
        }
    }

    private func scaledRecipe(_ recipe: Recipe) -> ScaledRecipe {
        proteinScaled ?? ((try? ScalingEngine.scale(recipe, toServings: servings)) ?? ScalingEngine.scale(recipe, by: .one))
    }

    @ViewBuilder
    private func content(for recipe: Recipe) -> some View {
        let scaled = scaledRecipe(recipe)
        let formatter = services.formatter

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if stored.imageData != nil {
                    RecipeImage(data: stored.imageData, title: recipe.title)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    HStack(spacing: 12) {
                        if let minutes = recipe.totalMinutes {
                            Label(minutes.minutesLabel, systemImage: "clock")
                        }
                        if let attribution = recipe.sourceAttribution {
                            if let url = recipe.sourceURL {
                                Link(destination: url) { Label(attribution, systemImage: "link") }
                            } else {
                                Label(attribution, systemImage: "text.book.closed")
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .padding(.horizontal)

                nutrition(scaled)

                if !proteinTargetHidden(recipe) {
                    proteinTargetField(recipe)
                }

                ingredientList(scaled, formatter: formatter)
                stepList(recipe)

                Text(Copy.nutritionDisclaimer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
                    .padding(.bottom, 90)
            }
        }
        .ignoresSafeArea(edges: stored.imageData != nil ? .top : [])
        .safeAreaInset(edge: .bottom) {
            ServingStepper(servings: $servings)
                .padding(.bottom, 8)
        }
        .onChange(of: servings) { _, _ in
            proteinScaled = nil
            proteinTarget = ""
        }
        .onAppear { servings = recipe.baseServings }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button {
                        exportURL = RecipeExport.file(for: [recipe], name: recipe.title)
                    } label: { Label("Export JSON", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack { RecipeEditorView(mode: .edit(stored)) }
        }
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
        }
        .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(stored)
                try? context.save()
                dismiss()
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func nutrition(_ scaled: ScaledRecipe) -> some View {
        if let per = scaled.perServingMacros, let total = scaled.totalMacros {
            let ringLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
            VStack(alignment: .leading, spacing: 12) {
                ringLayout {
                    MacroRingView(macros: per)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Per serving")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        MacroLegend(macros: per)
                        ConfidenceBadge(confidence: scaled.base.nutritionConfidence)
                    }
                }
                Text("Whole batch at \(servingsLabel(scaled.servings)): \(total.protein.grams) protein · \(total.fat.grams) fat · \(total.carbs.grams) carbs · \(total.calories.kcal)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Per-serving numbers don't change when you scale — only how much food you make.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .padding(.horizontal)
        } else {
            HStack {
                ConfidenceBadge(confidence: .unknown)
                Spacer()
                if services.hasNutritionKey {
                    Button("Look up nutrition") { Task { await lookupNutrition() } }
                        .font(.footnote)
                }
            }
            .padding(.horizontal)
        }
    }

    private func proteinTargetHidden(_ recipe: Recipe) -> Bool {
        (recipe.totalMacros?.protein ?? 0) <= 0
    }

    private func proteinTargetField(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Scale to total protein (g)", text: $proteinTarget)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyProteinTarget(recipe) }
                Button("Apply") { applyProteinTarget(recipe) }
                    .disabled(Double(proteinTarget) == nil)
            }
            if let proteinError {
                Text(proteinError).font(.caption).foregroundStyle(.red)
            } else if let proteinScaled {
                Text("Makes \(servingsLabel(proteinScaled.servings)) for \(Int(proteinScaled.totalMacros?.protein.rounded() ?? 0)) g protein.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func applyProteinTarget(_ recipe: Recipe) {
        guard let grams = Double(proteinTarget) else { return }
        do {
            proteinScaled = try ScalingEngine.scale(recipe, toTotalProtein: grams)
            proteinError = nil
        } catch ScalingError.servingsOutOfRange(let n) {
            proteinError = "That would be \(n) servings — the range is \(ScalingEngine.servingRange.lowerBound)–\(ScalingEngine.servingRange.upperBound)."
        } catch {
            proteinError = "Can't scale by protein for this recipe."
        }
    }

    private func ingredientList(_ scaled: ScaledRecipe, formatter: QuantityFormatter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients")
                .font(.title3.weight(.semibold))
            ForEach(scaled.ingredients) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatter.line(for: item))
                    if let note = item.note {
                        Label(note.message, systemImage: "hand.raised")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding(.horizontal)
    }

    private func stepList(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Method")
                .font(.title3.weight(.semibold))
            if recipe.steps.isEmpty {
                Text("No steps saved.").foregroundStyle(.secondary)
            }
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24, alignment: .trailing)
                    Text(step)
                }
            }
        }
        .padding(.horizontal)
    }

    private func servingsLabel(_ servings: Rational) -> String {
        if servings.isInteger { return "\(servings.numerator) servings" }
        return String(format: "%.1f servings", servings.doubleValue)
    }

    private func lookupNutrition() async {
        guard let recipe = stored.recipe else { return }
        let priced = await services.priceNutrition(for: recipe)
        stored.update(from: priced)
        try? context.save()
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum RecipeExport {
    /// Writes the recipes as pretty JSON to a temporary file for sharing.
    static func file(for recipes: [Recipe], name: String) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(recipes) else { return nil }
        let safeName = name.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.isEmpty ? "Proportion" : safeName).json")
        try? data.write(to: url, options: .atomic)
        return url
    }
}
