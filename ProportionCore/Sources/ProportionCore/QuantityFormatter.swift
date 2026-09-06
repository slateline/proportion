import Foundation

/// Turns exact quantities into what a cook expects to read.
///
/// Three things happen, in order:
/// 1. Optional cross-system conversion (cups → ml) if the user prefers it.
/// 2. Unit selection: the largest unit in the family that the amount fills
///    to its minimum — 3 tsp becomes 1 tbsp, 16 tbsp becomes 1 cup,
///    1000 g becomes 1 kg; and the reverse, so ½ tbsp reads as 1 ½ tsp.
/// 3. Rounding to a cook-friendly step: ⅛ for cups, ¼ for spoons, 5 g under
///    100 g and 25 g above. Amounts that are already a clean fraction
///    (⅓ cup) are preserved rather than forced onto the grid.
///
/// Rounding only ever affects display. The `Quantity` inside the recipe stays
/// exact, so the rounded value is recomputed from truth every time.
public struct QuantityFormatter: Sendable {
    public enum UnitSystem: Sendable {
        /// Show each quantity in the family it was authored in.
        case asAuthored
        case us
        case metric
    }

    public var unitSystem: UnitSystem

    public init(unitSystem: UnitSystem = .asAuthored) {
        self.unitSystem = unitSystem
    }

    // MARK: Public API

    public func string(for quantity: Quantity) -> String {
        let q = normalized(quantity)
        let number = numberString(q.amount, unit: q.unit)
        let name = q.unit.displayName(plural: q.amount > 1)
        return name.isEmpty ? number : "\(number) \(name)"
    }

    /// One ingredient line: "2 cups all-purpose flour, sifted" or "salt, to taste".
    public func line(for scaled: ScaledIngredient) -> String {
        let ingredient = scaled.ingredient
        var text: String
        if let quantity = scaled.quantity {
            text = "\(string(for: quantity)) \(ingredient.name)"
        } else if let descriptor = ingredient.descriptor, !descriptor.isEmpty {
            text = "\(ingredient.name), \(descriptor)"
        } else {
            text = ingredient.name
        }
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            text += ", \(preparation)"
        }
        return text
    }

    /// The quantity after system conversion, unit selection, and rounding.
    /// Exposed so the rules can be tested without going through strings.
    public func normalized(_ quantity: Quantity) -> Quantity {
        let q = convertedToPreferredSystem(quantity)
        let family = q.unit.family

        guard family.isConvertible else {
            let amount = roundNonZero(q.amount, steps: [Rational(1, 2)], preserving: [1, 2, 4])
            return Quantity(amount, q.unit)
        }

        if family == .metricMass || family == .metricVolume {
            // Metric rounds in the base unit (g / ml) first, then picks the
            // unit, so 999 g rounds up to 1000 g and is shown as 1 kg.
            let base = roundMetricBase(q.amountInBaseUnit, family: family)
            let unit = chooseUnit(baseAmount: base, in: family)
            return Quantity(base / unit.factorToBase, unit)
        }

        // US volume and imperial mass round in the chosen unit, because the
        // friendly fractions (¼ tsp, ⅛ cup) are per-unit. Rounding can push
        // an amount over the next unit's threshold (2.9 tsp → 3 tsp → 1 tbsp),
        // so re-select once after rounding.
        var base = q.amountInBaseUnit
        var unit = chooseUnit(baseAmount: base, in: family)
        for _ in 0..<3 {
            let rounded = roundInUnit(base / unit.factorToBase, unit: unit)
            base = rounded * unit.factorToBase
            let next = chooseUnit(baseAmount: base, in: family)
            if next == unit { break }
            unit = next
        }
        return Quantity(base / unit.factorToBase, unit)
    }

    // MARK: Unit selection

    /// Each family's units from largest to smallest, paired with the minimum
    /// base amount that unit is used for. A cup is only shown from ¼ cup up;
    /// below that the amount reads better in tablespoons.
    private static func ladder(for family: UnitFamily) -> [(MeasurementUnit, Rational)] {
        switch family {
        case .usVolume: return [(.cup, 12), (.tablespoon, 3), (.teaspoon, 0)]
        case .metricVolume: return [(.liter, 1000), (.milliliter, 0)]
        case .metricMass: return [(.kilogram, 1000), (.gram, 0)]
        case .imperialMass: return [(.pound, 16), (.ounce, 0)]
        case .count: return []
        }
    }

    private func chooseUnit(baseAmount: Rational, in family: UnitFamily) -> MeasurementUnit {
        let ladder = Self.ladder(for: family)
        for (unit, minimum) in ladder where baseAmount >= minimum {
            return unit
        }
        return ladder.last!.0
    }

    // MARK: Rounding

    private func roundMetricBase(_ amount: Rational, family: UnitFamily) -> Rational {
        let coarse: Rational
        if family == .metricMass {
            coarse = amount < 100 ? 5 : 25
        } else {
            coarse = amount < 100 ? 5 : 10
        }
        return roundNonZero(amount, steps: [coarse, 1], preserving: [])
    }

    private func roundInUnit(_ amount: Rational, unit: MeasurementUnit) -> Rational {
        switch unit {
        case .cup:
            return roundNonZero(amount, steps: [Rational(1, 8)], preserving: [1, 2, 3, 4, 6, 8])
        case .tablespoon, .teaspoon:
            // No ⅓-tsp measure exists, so thirds are not preserved for spoons.
            return roundNonZero(amount, steps: [Rational(1, 4), Rational(1, 8)], preserving: [1, 2, 4, 8])
        case .pound:
            return roundNonZero(amount, steps: [Rational(1, 8)], preserving: [1, 2, 4, 8])
        case .ounce:
            return roundNonZero(amount, steps: [Rational(1, 4)], preserving: [1, 2, 4, 8])
        default:
            return amount
        }
    }

    /// Rounds to the first step that doesn't collapse a real amount to zero.
    /// Amounts whose denominator is in `preserving` are already clean
    /// fractions and are returned untouched.
    private func roundNonZero(_ amount: Rational, steps: [Rational], preserving: Set<Int>) -> Rational {
        if preserving.contains(amount.denominator) { return amount }
        for step in steps {
            let rounded = amount.rounded(toNearest: step)
            if !rounded.isZero { return rounded }
        }
        // A positive amount too small for even the finest step shows as that step.
        return amount.isZero ? .zero : steps.last!
    }

    // MARK: Cross-system conversion

    private static let millilitersPerTeaspoon = 4.92892159375
    private static let gramsPerOunce = 28.349523125

    private func convertedToPreferredSystem(_ q: Quantity) -> Quantity {
        switch (unitSystem, q.unit.family) {
        case (.metric, .usVolume):
            return approximate(q.amountInBaseUnit.doubleValue * Self.millilitersPerTeaspoon, as: .milliliter)
        case (.metric, .imperialMass):
            return approximate(q.amountInBaseUnit.doubleValue * Self.gramsPerOunce, as: .gram)
        case (.us, .metricVolume):
            return approximate(q.amountInBaseUnit.doubleValue / Self.millilitersPerTeaspoon, as: .teaspoon)
        case (.us, .metricMass):
            return approximate(q.amountInBaseUnit.doubleValue / Self.gramsPerOunce, as: .ounce)
        default:
            return q
        }
    }

    private func approximate(_ value: Double, as unit: MeasurementUnit) -> Quantity {
        Quantity(Rational(approximating: value, maxDenominator: 1000), unit)
    }

    // MARK: Number rendering

    private func numberString(_ amount: Rational, unit: MeasurementUnit) -> String {
        switch unit {
        case .kilogram, .liter:
            return decimalString(amount.doubleValue, maxFractionDigits: 3)
        case .gram, .milliliter:
            return decimalString(amount.doubleValue, maxFractionDigits: 0)
        default:
            return mixedFractionString(amount)
        }
    }

    private func decimalString(_ value: Double, maxFractionDigits: Int) -> String {
        var s = String(format: "%.\(maxFractionDigits)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    private static let vulgarFractions: [Rational: String] = [
        Rational(1, 2): "½",
        Rational(1, 3): "⅓", Rational(2, 3): "⅔",
        Rational(1, 4): "¼", Rational(3, 4): "¾",
        Rational(1, 6): "⅙", Rational(5, 6): "⅚",
        Rational(1, 8): "⅛", Rational(3, 8): "⅜", Rational(5, 8): "⅝", Rational(7, 8): "⅞",
    ]

    private func mixedFractionString(_ amount: Rational) -> String {
        let negative = amount < 0
        let magnitude = negative ? -amount : amount
        let whole = magnitude.wholePart
        let fraction = magnitude.fractionalPart

        var text = ""
        if whole > 0 || fraction.isZero {
            text = "\(whole)"
        }
        if !fraction.isZero {
            let glyph = Self.vulgarFractions[fraction] ?? "\(fraction.numerator)/\(fraction.denominator)"
            text = text.isEmpty ? glyph : "\(text) \(glyph)"
        }
        return negative ? "-\(text)" : text
    }
}
