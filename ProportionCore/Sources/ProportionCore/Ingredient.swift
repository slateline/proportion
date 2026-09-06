import Foundation

/// One line of a recipe's ingredient list, stored structured.
///
/// The parser is required to split "2 cups flour, sifted" into its parts; the
/// app never stores that string and never tries to parse it back apart.
public struct Ingredient: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID

    /// Canonical item name: "all-purpose flour", not the whole line.
    public var name: String

    /// Structured amount. `nil` for non-numeric amounts, which live in
    /// `descriptor` and pass through scaling untouched.
    public var quantity: Quantity?

    /// Non-numeric amount text: "to taste", "a pinch", "1 pan", "salt for the water".
    public var descriptor: String?

    /// "finely diced", "room temperature".
    public var preparation: String?

    /// Resolved weight in grams for nutrition lookup, when known.
    public var grams: Double?

    /// False for items that don't scale linearly — leavening, spices, baking
    /// time, pan size. They are still scaled; the UI surfaces a note.
    public var isScalable: Bool

    /// Taxonomy tags walked up the hierarchy: parmesan → hard cheese → dairy.
    /// Populated by the ingredient taxonomy in a later build step.
    public var categoryTags: Set<String>

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: Quantity? = nil,
        descriptor: String? = nil,
        preparation: String? = nil,
        grams: Double? = nil,
        isScalable: Bool = true,
        categoryTags: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.descriptor = descriptor
        self.preparation = preparation
        self.grams = grams
        self.isScalable = isScalable
        self.categoryTags = categoryTags
    }
}
