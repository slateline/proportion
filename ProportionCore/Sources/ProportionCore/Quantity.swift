import Foundation

/// An exact amount of some unit: `3/2 cup`, `500 g`, `2 unitless`.
///
/// This is the stored form of every numeric ingredient amount. Display strings
/// ("1 ½ cups") are always rendered *from* a Quantity by `QuantityFormatter`
/// and never parsed back out of one.
public struct Quantity: Hashable, Codable, Sendable, CustomStringConvertible {
    public var amount: Rational
    public var unit: MeasurementUnit

    public init(_ amount: Rational, _ unit: MeasurementUnit) {
        self.amount = amount
        self.unit = unit
    }

    public init(_ amount: Int, _ unit: MeasurementUnit) {
        self.init(Rational(amount), unit)
    }

    public func scaled(by factor: Rational) -> Quantity {
        Quantity(amount * factor, unit)
    }

    /// The amount expressed in the family's base unit (tsp, ml, g, oz).
    /// Count units return the amount unchanged.
    public var amountInBaseUnit: Rational {
        amount * unit.factorToBase
    }

    /// Exact conversion to another unit in the same family. Returns nil across
    /// families or for count units, which never convert.
    public func converted(to target: MeasurementUnit) -> Quantity? {
        guard unit.family == target.family, unit.family.isConvertible else { return nil }
        return Quantity(amountInBaseUnit / target.factorToBase, target)
    }

    public var description: String {
        unit == .unitless ? "\(amount)" : "\(amount) \(unit.abbreviation)"
    }
}
