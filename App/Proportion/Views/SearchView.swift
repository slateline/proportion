import SwiftUI
import SwiftData
import ProportionCore

/// Conversational search. Each message becomes a structured query (by the
/// model when available, by keyword rules otherwise), the query is shown as
/// editable chips, and the results come from a local predicate over the
/// library — never from the model.
struct SearchView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredRecipe.createdAt, order: .reverse) private var stored: [StoredRecipe]

    @State private var input = ""
    @State private var query = SearchQuery()
    @State private var transcript: [Message] = []
    @State private var thinking = false
    @State private var showHidden = false
    @FocusState private var focused: Bool

    struct Message: Identifiable {
        let id = UUID()
        let isUser: Bool
        let text: String
        /// "Interpreted by Claude" / "interpreted offline (reason)".
        var footnote: String? = nil
    }

    private var decoded: [(stored: StoredRecipe, recipe: Recipe)] {
        stored.compactMap { s in s.recipe.map { (s, $0) } }
    }

    private var result: SearchResult {
        services.searchEngine.search(decoded.map(\.recipe), query: query, profile: showHidden ? nil : services.settings.dietaryProfile)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chips
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if transcript.isEmpty { intro }
                            ForEach(transcript) { message in
                                bubble(message)
                            }
                            if thinking {
                                HStack { ProgressView(); Text("Interpreting…").foregroundStyle(.secondary) }
                                    .font(.subheadline)
                                    .padding(.horizontal)
                            }
                            results
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.vertical)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: transcript.count) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                inputBar
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { reset() }.disabled(query.isEmpty && transcript.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let s = stored.first(where: { $0.recipeID == id }) {
                    RecipeDetailView(stored: s)
                }
            }
        }
        .onAppear { focused = true }
    }

    // MARK: Pieces

    @ViewBuilder
    private var chips: some View {
        let profileChips = services.settings.dietaryProfile.chips
        let all = profileChips + query.chips
        if !all.isEmpty {
            ChipRow(chips: all) { chip in
                query = query.removing(chip)
                transcript.append(Message(isUser: false, text: "Removed \(chip.label)."))
            }
            .background(.bar)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Describe what you feel like eating.")
                .font(.headline)
            Text("Try “high protein dinner, no dairy, under 30 minutes” or “something with the chicken thighs I have, but I'm sick of rice”. Follow-ups refine the search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !services.modelEnabled {
                Label("Offline interpretation — simple phrases work best.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func bubble(_ message: Message) -> some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.isUser { Spacer(minLength: 40) }
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Theme.accent.opacity(0.18) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !message.isUser { Spacer(minLength: 40) }
            }
            if let footnote = message.footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(footnote.contains("failed") ? .orange : .secondary)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal)
        .accessibilityLabel(message.isUser ? "You said: \(message.text)" : message.text)
    }

    @ViewBuilder
    private var results: some View {
        if !query.isEmpty || !transcript.isEmpty {
            let r = result
            VStack(alignment: .leading, spacing: 8) {
                if r.matches.isEmpty {
                    if let relaxation = r.relaxation {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(relaxation.message)
                            Button("Drop “\(relaxation.chip.label)”") {
                                query = relaxation.relaxedQuery
                                transcript.append(Message(isUser: false, text: "Dropped \(relaxation.chip.label)."))
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)
                    } else if !query.isEmpty {
                        Text("Nothing in your library matches yet.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                } else {
                    Text("\(r.matches.count) in your library")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal)
                    ForEach(r.matches, id: \.id) { recipe in
                        if let s = decoded.first(where: { $0.recipe.id == recipe.id })?.stored {
                            NavigationLink(value: s.recipeID) {
                                RecipeRowView(stored: s, recipe: recipe)
                                    .padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if r.hiddenByProfile.count > 0 && !showHidden {
                    Button("\(r.hiddenByProfile.count) hidden by your dietary profile — show") { showHidden = true }
                        .font(.footnote)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("What do you want to eat?", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(send)
                .accessibilityIdentifier("search-input")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("search-send")
        }
        .padding()
        .background(.bar)
    }

    // MARK: Actions

    private func send() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !thinking else { return }
        input = ""
        transcript.append(Message(isUser: true, text: message))
        thinking = true
        let interpreter = services.queryInterpreter
        let modelEnabled = services.modelEnabled
        let current = query.isEmpty ? nil : query
        Task {
            let outcome = await interpreter.interpretDetailed(message, refining: current)
            query = outcome.query
            thinking = false
            let count = result.matches.count
            let summary: String
            if outcome.query.isEmpty {
                summary = "Cleared the search."
            } else if count == 0 {
                summary = "Nothing matches that yet."
            } else {
                summary = "Here \(count == 1 ? "is" : "are") \(count) — the chips above show how I read that. Tap one to drop it."
            }

            // Say what did the interpreting, so a tester can tell the model
            // path from the offline one and see why a model call failed.
            var footnote: String? = nil
            switch outcome.source {
            case .model:
                footnote = "Interpreted by Claude"
            case .keyword:
                if let error = outcome.modelError {
                    footnote = "Claude failed (\(error)) — interpreted offline"
                } else if modelEnabled {
                    footnote = "Interpreted offline"
                }
            }
            transcript.append(Message(isUser: false, text: summary, footnote: footnote))
        }
    }

    private func reset() {
        query = SearchQuery()
        transcript = []
        showHidden = false
    }
}
