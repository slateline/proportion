import SwiftUI
import SwiftData
import CloudKit
import ProportionCore

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Query private var stored: [StoredRecipe]

    @State private var customExclusion = ""
    @State private var proteinTarget = ""
    @State private var fatTarget = ""
    @State private var carbsTarget = ""
    @State private var syncStatus = "Checking…"
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var settings = services.settings

        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Show quantities", selection: $settings.unitSystem) {
                        Text("As written").tag(QuantityFormatter.UnitSystem.asAuthored)
                        Text("US (cups, oz)").tag(QuantityFormatter.UnitSystem.us)
                        Text("Metric (g, ml)").tag(QuantityFormatter.UnitSystem.metric)
                    }
                    Stepper("Default servings: \(settings.defaultServings)", value: $settings.defaultServings, in: ScalingEngine.servingRange)
                }

                Section {
                    ForEach(DietaryPreset.allCases, id: \.self) { preset in
                        Toggle(preset.title, isOn: Binding(
                            get: { settings.dietaryProfile.presets.contains(preset) },
                            set: { on in
                                if on { settings.dietaryProfile.presets.insert(preset) } else { settings.dietaryProfile.presets.remove(preset) }
                            }))
                    }
                    ForEach(settings.dietaryProfile.customExclusions.sorted(), id: \.self) { term in
                        HStack {
                            Text("No \(term)")
                            Spacer()
                            Button(role: .destructive) {
                                settings.dietaryProfile.customExclusions.remove(term)
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red)
                            }
                            .accessibilityLabel("Remove \(term)")
                        }
                    }
                    HStack {
                        TextField("Always avoid… (e.g. cilantro)", text: $customExclusion)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addExclusion)
                        Button("Add", action: addExclusion)
                            .disabled(customExclusion.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Dietary profile")
                } footer: {
                    Text(DietaryProfile.disclaimer)
                }

                Section {
                    LabeledContent("Protein") { TextField("g", text: $proteinTarget).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    LabeledContent("Fat") { TextField("g", text: $fatTarget).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    LabeledContent("Carbs") { TextField("g", text: $carbsTarget).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    Button("Save targets") { saveTargets() }
                    if settings.dailyTargets != nil {
                        Button("Clear targets", role: .destructive) { settings.dailyTargets = nil; proteinTarget = ""; fatTarget = ""; carbsTarget = "" }
                    }
                } header: {
                    Text("Daily targets (optional)")
                }

                Section {
                    Toggle("Use Claude to read recipes and searches", isOn: Binding(
                        get: { services.hasModelKey && settings.useModelForParsing },
                        set: { settings.useModelForParsing = $0 }))
                        .disabled(!services.hasModelKey)
                } header: {
                    Text("Privacy")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Copy.modelPrivacy)
                        if !services.hasModelKey {
                            Text("No Anthropic key is configured in this build, so nothing is ever sent to a model.")
                        }
                        Text("Nutrition lookups send ingredient names to the USDA FoodData Central service\(services.hasNutritionKey ? "" : " (not configured in this build)"). Your recipes are stored on this phone and in your private iCloud database. There are no analytics and no account.")
                    }
                }

                Section("Sync & data") {
                    LabeledContent("iCloud", value: syncStatus)
                    LabeledContent("Recipes", value: "\(stored.count)")
                    Button("Export all recipes as JSON") {
                        let recipes = stored.compactMap(\.recipe)
                        exportURL = RecipeExport.file(for: recipes, name: "Proportion recipes")
                    }
                    .disabled(stored.isEmpty)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Text(Copy.nutritionDisclaimer).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { await checkSync() }
            .onAppear(perform: loadTargets)
            .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
        }
    }

    private func addExclusion() {
        let term = services.taxonomy.canonicalName(for: customExclusion)
        guard !term.isEmpty else { return }
        services.settings.dietaryProfile.customExclusions.insert(term)
        customExclusion = ""
    }

    private func loadTargets() {
        guard let t = services.settings.dailyTargets else { return }
        proteinTarget = String(Int(t.protein))
        fatTarget = String(Int(t.fat))
        carbsTarget = String(Int(t.carbs))
    }

    private func saveTargets() {
        let p = Double(proteinTarget) ?? 0, f = Double(fatTarget) ?? 0, c = Double(carbsTarget) ?? 0
        services.settings.dailyTargets = (p + f + c) > 0 ? Macros(protein: p, fat: f, carbs: c) : nil
    }

    private func checkSync() async {
        // `CKContainer.default()` raises an Objective-C exception (not a Swift
        // error) when the build lacks the iCloud entitlement — e.g. an unsigned
        // CI or simulator build — and that takes the whole app down. Naming the
        // container explicitly returns the failure as an error instead.
        if ProportionApp.isUITesting {
            syncStatus = "Unavailable in tests"
            return
        }
        do {
            let status = try await CKContainer(identifier: "iCloud.com.proportion.app").accountStatus()
            switch status {
            case .available: syncStatus = "On"
            case .noAccount: syncStatus = "No iCloud account"
            case .restricted: syncStatus = "Restricted"
            case .couldNotDetermine: syncStatus = "Unknown"
            case .temporarilyUnavailable: syncStatus = "Temporarily unavailable"
            @unknown default: syncStatus = "Unknown"
            }
        } catch {
            syncStatus = "Unavailable"
        }
    }
}
