import SwiftUI
import ProportionCore

/// The parsed query as chips. Query chips can be tapped away; profile chips
/// are locked and only show a padlock — they are changed in Settings.
struct ChipRow: View {
    let chips: [QueryChip]
    var onRemove: ((QueryChip) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    ChipView(chip: chip) {
                        if !chip.isLocked { onRemove?(chip) }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

struct ChipView: View {
    let chip: QueryChip
    var action: () -> Void

    private var tint: Color {
        switch chip.kind {
        case .exclude, .profile: return .red
        case .include: return Theme.carbs
        case .protein, .carbs, .fat, .calories: return Theme.protein
        default: return Theme.accent
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if chip.isLocked {
                    Image(systemName: "lock.fill").font(.caption2)
                }
                Text(chip.label)
                if !chip.isLocked {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(chip.isLocked)
        .accessibilityLabel(chip.isLocked ? "\(chip.label), from your dietary profile" : "Remove \(chip.label)")
    }
}

/// Serving count control, pinned to the bottom of the detail screen.
struct ServingStepper: View {
    @Binding var servings: Int

    var body: some View {
        HStack(spacing: 16) {
            button("minus", enabled: servings > ScalingEngine.servingRange.lowerBound) { servings -= 1 }
                .accessibilityIdentifier("servings-decrement")
            VStack(spacing: 0) {
                Text("\(servings)")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(servings == 1 ? "serving" : "servings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 72)
            button("plus", enabled: servings < ScalingEngine.servingRange.upperBound) { servings += 1 }
                .accessibilityIdentifier("servings-increment")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .sensoryFeedback(.selection, trigger: servings)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Servings")
        .accessibilityValue("\(servings)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if servings < ScalingEngine.servingRange.upperBound { servings += 1 }
            case .decrement: if servings > ScalingEngine.servingRange.lowerBound { servings -= 1 }
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .disabled(!enabled)
        .tint(Theme.accent)
    }
}
