import XCTest
@testable import ProportionCore

final class RationalTests: XCTestCase {

    func testNormalisation() {
        XCTAssertEqual(Rational(2, 4), Rational(1, 2))
        XCTAssertEqual(Rational(3, -6).numerator, -1)
        XCTAssertEqual(Rational(3, -6).denominator, 2)
        XCTAssertEqual(Rational(0, 5), .zero)
        XCTAssertEqual(Rational(0, 5).denominator, 1)
        XCTAssertEqual(Rational(-4, -8), Rational(1, 2))
    }

    func testArithmetic() {
        XCTAssertEqual(Rational(1, 2) + Rational(1, 3), Rational(5, 6))
        XCTAssertEqual(Rational(1) - Rational(1, 3), Rational(2, 3))
        XCTAssertEqual(Rational(3, 4) * 2, Rational(3, 2))
        XCTAssertEqual(2 * Rational(3, 4), Rational(3, 2))
        XCTAssertEqual(Rational(1, 2) / Rational(1, 4), 2)
        XCTAssertEqual(-Rational(1, 3), Rational(-1, 3))
    }

    func testComparison() {
        XCTAssertLessThan(Rational(1, 3), Rational(1, 2))
        XCTAssertGreaterThan(Rational(2), Rational(3, 2))
        XCTAssertEqual(Rational(6, 4), Rational(3, 2))
        XCTAssertLessThan(Rational(-1, 2), .zero)
    }

    func testParts() {
        let x = Rational(7, 4)
        XCTAssertEqual(x.wholePart, 1)
        XCTAssertEqual(x.fractionalPart, Rational(3, 4))
        XCTAssertTrue(Rational(4, 2).isInteger)
        XCTAssertFalse(Rational(1, 2).isInteger)
        XCTAssertEqual(Rational(3, 2).doubleValue, 1.5)
    }

    func testRoundingToStep() {
        XCTAssertEqual(Rational(5, 12).rounded(toNearest: Rational(1, 8)), Rational(3, 8))
        XCTAssertEqual(Rational(29, 10).rounded(toNearest: Rational(1, 4)), 3)
        XCTAssertEqual(Rational(133).rounded(toNearest: 5), 135)
        XCTAssertEqual(Rational(47).rounded(toNearest: 5), 45)
        XCTAssertEqual(Rational(112).rounded(toNearest: 25), 100)
        XCTAssertEqual(Rational(113).rounded(toNearest: 25), 125)
        XCTAssertEqual(Rational(1234).rounded(toNearest: 25), 1225)
    }

    func testRoundingHalvesAwayFromZero() {
        XCTAssertEqual(Rational(1, 8).rounded(toNearest: Rational(1, 4)), Rational(1, 4))
        XCTAssertEqual(Rational(-1, 8).rounded(toNearest: Rational(1, 4)), Rational(-1, 4))
        XCTAssertEqual(Rational(5, 2).rounded(toNearest: 1), 3)
    }

    func testApproximation() {
        XCTAssertEqual(Rational(approximating: 1.0 / 3.0), Rational(1, 3))
        XCTAssertEqual(Rational(approximating: 1.5), Rational(3, 2))
        XCTAssertEqual(Rational(approximating: 0.1), Rational(1, 10))
        XCTAssertEqual(Rational(approximating: 0), .zero)
        XCTAssertEqual(Rational(approximating: -0.75), Rational(-3, 4))
        XCTAssertEqual(Rational(approximating: 2.7, maxDenominator: 1), 3)
        XCTAssertEqual(Rational(approximating: Double.pi, maxDenominator: 1000), Rational(355, 113))
    }

    func testDescription() {
        XCTAssertEqual(Rational(3, 4).description, "3/4")
        XCTAssertEqual(Rational(2).description, "2")
        XCTAssertEqual(Rational(-1, 2).description, "-1/2")
    }

    func testCodableRoundTrip() throws {
        let original = Rational(7, 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Rational.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodingNormalisesUnreducedInput() throws {
        let json = #"{"numerator":2,"denominator":4}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Rational.self, from: json)
        XCTAssertEqual(decoded, Rational(1, 2))
    }

    func testDecodingRejectsZeroDenominator() {
        let json = #"{"numerator":1,"denominator":0}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Rational.self, from: json))
    }
}
