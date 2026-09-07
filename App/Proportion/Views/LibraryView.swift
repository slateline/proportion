import SwiftUI
import SwiftData
import ProportionCore

struct LibraryView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \StoredRecipe.createdAt, order: .reverse) private var stored: [StoredRecipe]

    @State private var titleFilter = ""
    @State private var sort: StoredRecipe.SortOrder = .newest
    @State private var quickFilter = SearchQuery()
    @State private var showHidden = false
    @State private var showSearch = false
    @State private var showNew = false

    private var decoded: [(stored: StoredRecipe, recipe: Recipe)] {
        stored.sorted(using: sort.descriptors).compactMap { s in s.recipe.map { (s, $0) } }
    }

    private var result: SearchResult {
        var query = quickFilter
        let trimmed = titleFilter.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { query.text = trimmed }
        return services.searchEngine.search(decoded.map(\.recipe), query: query, profile: showHidden ? nil : services.settings.dietaryProfile)
    }

    private func storedFor(_ recipe: Recipe) -> StoredRecipe? {
        decoded.first { $0.recipe.id == recipe.id }?.stored
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if stored.isEmpty {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Capture one from a photo, a link, or pasted text, or write it in yourself.")
                    } actions: {
                        Button("Add a recipe") { showNew = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        askBar
                        if !quickFilter.isEmpty {
                            ChipRow(chips: quickFilter.chips) { quickFilter = quickFilter.removing($0) }
                        }
                        let r = result
                        if r.matches.isEmpty {
                            ContentUnavailableView.search
                        }
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(r.matches, id: \.id) { recipe in
                                if let s = storedFor(recipe) {
                                    NavigationLink(value: s.recipeID) {
                                        RecipeCardView(stored: s, recipe: recipe)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("recipe-card")
                                }
                            }
                        }
                        .padding(.horizontal)
                        hiddenNotice(count: r.hiddenByProfile.count)
                        Text(Copy.nutritionDisclaimer)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: UUID.self) { id in
                if let s = stored.first(where: { $0.recipeID == id }) {
                    RecipeDetailView(stored: s)
                }
            }
            .searchable(text: $titleFilter, prompt: "Filter by title or ingredient")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(StoredRecipe.SortOrder.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("High protein (≥ 30 g)") { quickFilter.minProtein = 30 }
                        Button("Low carb (≤ 20 g)") { quickFilter.maxCarbs = 20 }
                        Button("Under 30 minutes") { quickFilter.maxMinutes = 30 }
                        Button("Under 500 kcal") { quickFilter.maxCalories = 500 }
                        if !quickFilter.isEmpty {
                            Divider()
                            Button("Clear filters", role: .destructive) { quickFilter = SearchQuery() }
                        }
                    } label: {
                        Label("Filter", systemImage: quickFilter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Label("New recipe", systemImage: "plus") }
                        .accessibilityIdentifier("library-new")
                }
            }
            .sheet(isPresented: $showSearch) { SearchView() }
            .sheet(isPresented: $showNew) {
                NavigationStack { RecipeEditorView(mode: .blank) }
            }
        }
    }

    private var askBar: some View {
        Button { showSearch = true } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Ask for a recipe — “high protein, no dairy, under 30 minutes”")
                    .lineLimit(1)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 4)
        .accessibilityLabel("Search recipes by describing what you want")
    }

    @ViewBuilder
    private func hiddenNotice(count: Int) -> some View {
        if count > 0 && !showHidden {
            Button("\(count) hidden by your dietary profile — show") { showHidden = true }
                .font(.footnote)
                .padding(.top, 8)
        } else if showHidden && !services.settings.dietaryProfile.isEmpty {
            Button("Showing recipes outside your dietary profile — hide") { showHidden = false }
                .font(.footnote)
                .padding(.top, 8)
        }
    }
}
