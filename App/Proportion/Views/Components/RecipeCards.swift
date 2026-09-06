import SwiftUI
import ProportionCore

/// Grid card for the library. Photography carries the card when there is
/// any; otherwise a quiet tinted block so text-only recipes don't look broken.
struct RecipeCardView: View {
    let stored: StoredRecipe
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RecipeImage(data: stored.imageData, title: recipe.title)
                    .frame(height: 140)
                    .clipped()
                if let minutes = recipe.totalMinutes {
                    Text(minutes.minutesLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                MacroStrip(macros: recipe.perServingMacros)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// List row for search results.
struct RecipeRowView: View {
    let stored: StoredRecipe
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(data: stored.imageData, title: recipe.title)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.headline).lineLimit(2)
                HStack(spacing: 8) {
                    MacroStrip(macros: recipe.perServingMacros)
                    if let minutes = recipe.totalMinutes {
                        Text("· \(minutes.minutesLabel)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecipeImage: View {
    let data: Data?
    let title: String

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            ZStack {
                LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(title.prefix(1)).uppercased())
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
        }
    }
}
