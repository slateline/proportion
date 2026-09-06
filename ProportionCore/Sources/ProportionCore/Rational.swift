import Foundation

/// An exact rational number.
///
/// Ingredient quantities are stored and scaled as rationals, never as floats,
/// so that repeatedly changing the serving count can never accumulate drift:
/// scaling 2 cups to 7 servings and back to 4 yields exactly 2 cups.
public struct Rational: Hashable, Sendable {
    public let numerator: Int
    /// Always positive; the sign lives on the numerator.
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int = 1) {
        precondition(denominator != 0, "Rational denominator cannot be zero")
        var n = numerator
        var d = denominator
        if d < 0 {
            n = -n
            d = -d
        }
        let g = Rational.gcd(abs(n), d)
        if g > 1 {
            n /= g
            d /= g
        }
        self.numerator = n
        self.denominator = d
    }

    public static let zero = Rational(0)
    public static let one = Rational(1)

    /// The best rational approximation of `value` whose denominator does not
    /// exceed `maxDenominator`, found by walking the continued-fraction
    /// expansion. Used where a float unavoidably enters the system (a protein
    /// target, a metric/US conversion) so it is pinned to an exact value once.
    public init(approximating value: Double, maxDenominator: Int = 1000) {
        precondition(value.isFinite, "Cannot approximate a non-finite value")
        precondition(maxDenominator >= 1, "maxDenominator must be at least 1")
        let negative = value < 0
        var x = abs(value)
        var h0 = 0, h1 = 1
        var k0 = 1, k1 = 0
        var best: (Int, Int)? = nil
        for _ in 0..<64 {
            guard x < Double(Int.max / 4) else { break }
            let a = Int(x.rounded(.down))
            let (ah1, overflow1) = a.multipliedReportingOverflow(by: h1)
            let (ak1, overflow2) = a.multipliedReportingOverflow(by: k1)
            if overflow1 || overflow2 { break }
            let h2 = ah1 + h0
            let k2 = ak1 + k0
            if k2 > maxDenominator { break }
            (h0, h1, k0, k1) = (h1, h2, k1, k2)
            best = (h1, k1)
            let fraction = x - Double(a)
            if fraction < 1e-12 { break }
            x = 1 / fraction
        }
        let (n, d) = best ?? (Int(abs(value).rounded()), 1)
        self.init(negative ? -n : n, d)
    }

    public var doubleValue: Double { Double(numerator) / Double(denominator) }
    public var isInteger: Bool { denominator == 1 }
    public var isZero: Bool { numerator == 0 }

    /// Whole part, truncated toward zero: 7/4 → 1.
    public var wholePart: Int { numerator / denominator }

    /// The remainder after `wholePart`, carrying the same sign: 7/4 → 3/4.
    public var fractionalPart: Rational { Rational(numerator % denominator, denominator) }

    /// Rounds to the nearest multiple of `step`; halves round away from zero.
    public func rounded(toNearest step: Rational) -> Rational {
        precondition(step.numerator > 0, "Rounding step must be positive")
        let q = self / step
        // floor(|q| + 1/2) in integer arithmetic
        let magnitude = (2 * abs(q.numerator) + q.denominator) / (2 * q.denominator)
        let count = q.numerator < 0 ? -magnitude : magnitude
        return Rational(count) * step
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}

extension Rational: Comparable {
    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }
}

extension Rational: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self.init(value) }
}

extension Rational: CustomStringConvertible {
    public var description: String {
        isInteger ? "\(numerator)" : "\(numerator)/\(denominator)"
    }
}

public extension Rational {
    static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
                 lhs.denominator * rhs.denominator)
    }

    static func - (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator,
                 lhs.denominator * rhs.denominator)
    }

    static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    static func / (lhs: Rational, rhs: Rational) -> Rational {
        precondition(!rhs.isZero, "Division by zero")
        return Rational(lhs.numerator * rhs.denominator, lhs.denominator * rhs.numerator)
    }

    static prefix func - (value: Rational) -> Rational {
        Rational(-value.numerator, value.denominator)
    }

    static func * (lhs: Rational, rhs: Int) -> Rational { lhs * Rational(rhs) }
    static func * (lhs: Int, rhs: Rational) -> Rational { Rational(lhs) * rhs }
}

extension Rational: Codable {
    private enum CodingKeys: String, CodingKey { case numerator, denominator }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let n = try container.decode(Int.self, forKey: .numerator)
        let d = try container.decode(Int.self, forKey: .denominator)
        guard d != 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .denominator, in: container,
                debugDescription: "Rational denominator cannot be zero")
        }
        // Route through the normalising initialiser so hand-edited or
        // legacy data can never produce an un-reduced value.
        self.init(n, d)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(numerator, forKey: .numerator)
        try container.encode(denominator, forKey: .denominator)
    }
}
