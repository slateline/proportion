import Foundation

/// Turns an ingredient's quantity into grams so it can be priced against a
/// per-100 g nutrition record.
///
/// Mass units are exact. Volumes need a density, counts need a per-item
/// weight; both come from small bundled tables keyed by canonical name and
/// walked up the taxonomy, so "cheddar" falls back to "cheese". Anything the
/// tables can't place returns nil and the ingredient is reported unresolved
/// rather than guessed silently.
public struct GramEstimator: Sendable {
    public var taxonomy: IngredientTaxonomy
    public var gramsPerCup: [String: Double]
    public var gramsPerPiece: [String: Double]

    public init(
        taxonomy: IngredientTaxonomy = .standard,
        gramsPerCup: [String: Double] = GramEstimator.defaultGramsPerCup,
        gramsPerPiece: [String: Double] = GramEstimator.defaultGramsPerPiece
    ) {
        self.taxonomy = taxonomy
        self.gramsPerCup = gramsPerCup
        self.gramsPerPiece = gramsPerPiece
    }

    static let gramsPerOunce = 28.349523125
    static let millilitersPerCup = 236.5882365

    public func grams(for ingredient: Ingredient) -> Double? {
        if let grams = ingredient.grams { return grams }
        guard let quantity = ingredient.quantity else { return nil }
        let amount = quantity.amount.doubleValue
        guard amount > 0 else { return nil }

        switch quantity.unit.family {
        case .metricMass:
            return quantity.amountInBaseUnit.doubleValue
        case .imperialMass:
            return quantity.amountInBaseUnit.doubleValue * Self.gramsPerOunce
        case .usVolume:
            guard let perCup = lookup(gramsPerCup, for: ingredient.name) else { return nil }
            let cups = quantity.amountInBaseUnit.doubleValue / 48
            return cups * perCup
        case .metricVolume:
            guard let perCup = lookup(gramsPerCup, for: ingredient.name) else { return nil }
            let milliliters = quantity.amountInBaseUnit.doubleValue
            return milliliters / Self.millilitersPerCup * perCup
        case .count:
            return countGrams(amount: amount, unit: quantity.unit, name: ingredient.name)
        }
    }

    private func countGrams(amount: Double, unit: MeasurementUnit, name: String) -> Double? {
        let each: Double?
        switch unit {
        case .unitless, .piece:
            each = lookup(gramsPerPiece, for: name)
        case .clove:
            each = lookup(gramsPerPiece, for: name + " clove") ?? 3
        case .slice:
            each = lookup(gramsPerPiece, for: name + " slice") ?? lookup(Self.defaultGramsPerSlice, for: name)
        case .can:
            each = lookup(gramsPerPiece, for: name + " can") ?? 400
        case .stick:
            each = 113
        case .bunch:
            each = lookup(gramsPerPiece, for: name + " bunch") ?? 60
        default:
            each = nil
        }
        guard let each else { return nil }
        return amount * each
    }

    /// Exact name first, then each ancestor in the taxonomy.
    private func lookup(_ table: [String: Double], for name: String) -> Double? {
        let canonical = taxonomy.canonicalName(for: name)
        if let direct = table[canonical] { return direct }
        for ancestor in taxonomy.ancestors(of: canonical) {
            if let value = table[ancestor] { return value }
        }
        return nil
    }

    // MARK: Tables

    /// Grams in one US cup. Values are typical for the form a recipe means
    /// (flour spooned, cheese shredded, nuts whole).
    public static let defaultGramsPerCup: [String: Double] = [
        "water": 237, "milk": 245, "cream": 238, "heavy cream": 238, "buttermilk": 245,
        "yogurt": 245, "greek yogurt": 285, "sour cream": 240, "butter": 227, "ghee": 220,
        "coconut milk": 240, "almond milk": 240, "oat milk": 240, "soy milk": 243,
        "olive oil": 216, "vegetable oil": 218, "canola oil": 218, "coconut oil": 218,
        "avocado oil": 218, "peanut oil": 216, "sesame oil": 218,
        "flour": 125, "all-purpose flour": 125, "bread flour": 127, "cake flour": 114,
        "whole wheat flour": 120, "almond flour": 96, "coconut flour": 112, "rice flour": 158,
        "cornstarch": 128, "cornmeal": 138, "semolina": 167, "breadcrumbs": 108, "panko": 50,
        "rolled oats": 90, "oat": 90, "quinoa": 170, "rice": 185, "couscous": 173, "bulgur": 140,
        "lentil": 192, "chickpea": 164, "black bean": 172, "kidney bean": 177,
        "sugar": 200, "brown sugar": 220, "powdered sugar": 120, "superfine sugar": 200,
        "honey": 340, "maple syrup": 315, "corn syrup": 328,
        "cocoa powder": 85, "chocolate chips": 170, "dark chocolate": 170,
        "cheese": 113, "parmesan": 90, "pecorino": 90, "cheddar": 113, "mozzarella": 112,
        "feta": 150, "ricotta": 246, "cream cheese": 232, "cottage cheese": 226,
        "peanut butter": 258, "almond butter": 256, "tahini": 240,
        "almond": 143, "walnut": 117, "cashew": 137, "pecan": 109, "pistachio": 123,
        "hazelnut": 135, "pine nut": 135, "peanut": 146, "sesame seed": 144,
        "salt": 288, "baking soda": 230, "baking powder": 192, "yeast": 150,
        "spinach": 30, "kale": 67, "lettuce": 47, "broccoli": 91, "cauliflower": 107,
        "mushroom": 70, "onion": 160, "carrot": 128, "celery": 101, "bell pepper": 149,
        "tomato": 180, "tomato sauce": 245, "tomato paste": 262, "corn": 154, "green pea": 145,
        "blueberry": 148, "strawberry": 152, "raspberry": 123, "banana": 225, "apple": 125,
        "stock": 240, "chicken stock": 240, "chicken broth": 240, "beef broth": 240,
        "vegetable stock": 240, "wine": 235, "beer": 237, "soy sauce": 255, "fish sauce": 272,
        "ketchup": 272, "mayonnaise": 220, "coconut": 80, "coconut cream": 240,
        "ground beef": 225, "chicken": 140, "shrimp": 150,
    ]

    /// Grams per one item, for "2 eggs", "1 onion".
    public static let defaultGramsPerPiece: [String: Double] = [
        "egg": 50, "egg white": 33, "egg yolk": 17, "large egg": 50,
        "onion": 110, "red onion": 110, "shallot": 25, "garlic": 3, "garlic clove": 3,
        "leek": 90, "spring onion": 15,
        "tomato": 123, "potato": 213, "sweet potato": 130, "carrot": 61, "celery": 40,
        "bell pepper": 119, "jalapeno": 14, "zucchini": 196, "cucumber": 300, "eggplant": 550,
        "avocado": 150, "mushroom": 18, "corn": 90,
        "lemon": 58, "lime": 44, "orange": 131, "apple": 182, "banana": 118,
        "chicken breast": 174, "chicken thigh": 83, "chicken wing": 30,
        "salmon": 170, "pork chop": 150, "sausage": 75, "bacon": 12, "bacon slice": 12,
        "bread": 30, "bread slice": 30, "flour tortilla": 45, "corn tortilla": 26, "pita": 60,
        "tofu": 350, "chickpea can": 400, "black bean can": 425, "tomato can": 400,
        "coconut milk can": 400, "tuna can": 140,
        "parsley bunch": 60, "coriander bunch": 50, "basil bunch": 30, "kale bunch": 200,
        "spinach bunch": 340, "mint bunch": 25, "dill bunch": 25,
    ]

    static let defaultGramsPerSlice: [String: Double] = [
        "bread": 30, "cheese": 28, "bacon": 12, "tomato": 20, "lemon": 8, "onion": 14, "ham": 28,
    ]
}
