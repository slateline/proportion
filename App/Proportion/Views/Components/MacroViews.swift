import SwiftUI
import ProportionCore

/// A ring split by each macro's share of calories, with the total in the middle.
struct MacroRingView: View {
    let macros: Macros
    var size: CGFloat = 132
    var lineWidth: CGFloat = 14

    private var shares: (protein: Double, fat: Double, carbs: Double) {
        let calories = macros.calories
        guard calories > 0 else { return (0, 0, 0) }
        return (macros.protein * 4 / calories, macros.fat * 9 / calories, macros.carbs * 4 / calories)
    }

    var body: some View {
        let s = shares
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
            segment(from: 0, to: s.protein, color: Theme.protein)
            segment(from: s.protein, to: s.protein + s.fat, color: Theme.fat)
            segment(from: s.protein + s.fat, to: min(1, s.protein + s.fat + s.carbs), color: Theme.carbs)
            VStack(spacing: 0) {
                Text("\(Int(macros.calories.rounded()))")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macros.calories.kcal) per serving. \(macros.protein.grams) protein, \(macros.fat.grams) fat, \(macros.carbs.grams) carbohydrate.")
    }

    private func segment(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: from, to: max(from, to))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}

struct MacroLegend: View {
    let macros: Macros

    var body: some View {
        HStack(spacing: 12) {
            MacroPill(label: "Protein", value: macros.protein, color: Theme.protein)
            MacroPill(label: "Fat", value: macros.fat, color: Theme.fat)
            MacroPill(label: "Carbs", value: macros.carbs, color: Theme.carbs)
        }
    }
}

struct MacroPill: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(value.grams)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Compact "P 32 · F 12 · C 40" strip for cards and rows.
struct MacroStrip: View {
    let macros: Macros?

    var body: some View {
        if let macros {
            HStack(spacing: 8) {
                stat("P", macros.protein, Theme.protein)
                stat("F", macros.fat, Theme.fat)
                stat("C", macros.carbs, Theme.carbs)
            }
            .font(.caption.monospacedDigit())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(macros.protein.grams) protein, \(macros.fat.grams) fat, \(macros.carbs.grams) carbs per serving")
        } else {
            Text("No nutrition data")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func stat(_ letter: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter).foregroundStyle(color).fontWeight(.bold)
            Text("\(Int(value.rounded()))")
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: NutritionConfidence

    var body: some View {
        Label(confidence.label, systemImage: confidence.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(confidence.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidence.color.opacity(0.12), in: Capsule())
    }
}
