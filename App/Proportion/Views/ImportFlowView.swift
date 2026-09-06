import SwiftUI
import ProportionCore

/// Runs one import job and hands the result to the review screen. Failures
/// never dead-end: the user can retry or drop into manual entry with any text
/// that was recovered already filled in.
struct ImportFlowView: View {
    let title: String
    let job: @Sendable () async throws -> RecipeDraft
    var onFinished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var attempt = 0

    private enum Phase {
        case loading
        case review(RecipeDraft)
        case failed(message: String, recoveredText: String?)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the recipe…").foregroundStyle(.secondary)
                    }
                case .review(let draft):
                    RecipeEditorView(mode: .review(draft)) { _ in
                        onFinished?()
                        dismiss()
                    }
                case .failed(let message, let recoveredText):
                    ContentUnavailableView {
                        Label("Couldn't read that", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { attempt += 1 }
                        Button("Enter it manually") {
                            phase = .review(RecipeDraft(
                                title: "",
                                ingredientLines: recoveredText.map { $0.components(separatedBy: .newlines) } ?? [],
                                source: .manual))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished?(); dismiss() }
                }
            }
        }
        .task(id: attempt) {
            phase = .loading
            do {
                phase = .review(try await job())
            } catch RecipeImporter.ImportError.nothingFound(let text) {
                phase = .failed(message: "No recipe could be found there. You can type it in instead.", recoveredText: text)
            } catch {
                phase = .failed(message: error.localizedDescription, recoveredText: nil)
            }
        }
    }
}
