import SwiftUI
import ProportionCore

/// One restrained accent, three macro colours, and nothing else. Everything
/// else is system colour so Dark Mode and Increase Contrast come for free.
enum Theme {
    static let accent = Color(red: 0.76, green: 0.36, blue: 0.22)
    static let protein = Color(red: 0.22, green: 0.47, blue: 0.78)
    static let fat = Color(red: 0.86, green: 0.62, blue: 0.18)
    static let carbs = Color(red: 0.40, green: 0.64, blue: 0.34)

    static let cardCorner: CGFloat = 16
}

extension Double {
    /// "32 g" — whole grams; recipes don't need decimals here.
    var grams: String { "\(Int(rounded())) g" }
    var kcal: String { "\(Int(rounded())) kcal" }
}

extension Int {
    var minutesLabel: String {
        if self >= 60 {
            let h = self / 60, m = self % 60
            return m == 0 ? "\(h) h" : "\(h) h \(m) min"
        }
        return "\(self) min"
    }
}

extension NutritionConfidence {
    var label: String {
        switch self {
        case .verified: return "Verified"
        case .partiallyEstimated: return "Partly estimated"
        case .estimated: return "Estimated"
        case .unknown: return "No nutrition data"
        }
    }

    var symbol: String {
        switch self {
        case .verified: return "checkmark.seal"
        case .partiallyEstimated, .estimated: return "questionmark.circle"
        case .unknown: return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .verified: return .green
        case .partiallyEstimated, .estimated: return .orange
        case .unknown: return .secondary
        }
    }
}

/// Shown wherever nutrition numbers appear.
enum Copy {
    static let nutritionDisclaimer = "Nutrition values are approximate and are not medical advice."
    static let modelPrivacy = "When on, recipe text you capture is sent to Anthropic's Claude to be read into ingredients and steps, and search messages are sent to be interpreted. Photos stay on your phone; only text recognised on-device is sent unless the text can't be read. When off, Proportion uses its built-in parsers only."
}
