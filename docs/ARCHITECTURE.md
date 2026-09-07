# Architecture

Proportion is split into a platform-independent engine and a thin app layer.

```
┌─────────────────────────────────────────────────────────┐
│  App/  (SwiftUI, SwiftData + CloudKit, Share Extension)  │
│  Views · StoredRecipe · RecipeImporter · Claude adapters │
└──────────────────────────┬──────────────────────────────┘
                           │ value types only
┌──────────────────────────▼──────────────────────────────┐
│  ProportionCore/  (Swift package, Foundation only)       │
│  Rational · Units · ScalingEngine · QuantityFormatter    │
│  IngredientTaxonomy · parsers · Nutrition · Search       │
└─────────────────────────────────────────────────────────┘
```

Everything that can be wrong in an interesting way lives in the core, where it
is unit-tested. The app layer holds views, persistence, networking adapters,
and platform features (OCR, camera, share sheet, CloudKit).

## Core package

| Area | Files | Responsibility |
|---|---|---|
| Model | `Rational`, `Units`, `Quantity`, `Macros`, `Ingredient`, `Recipe` | Exact quantities; unit families; the recipe value type |
| Scaling | `ScalingEngine`, `QuantityFormatter` | Non-destructive scaling by servings or protein target; unit promotion/demotion; display rounding |
| Taxonomy | `IngredientTaxonomy`, `TaxonomyData` | Canonical names and the category hierarchy (~400 terms) behind exclusions and nutrition lookup |
| Parsing | `IngredientLineParser`, `PlainTextRecipeParser`, `HTMLTextExtractor`, `JSONLDRecipeExtractor`, `RecipeDraft` | Deterministic structuring of lines, pasted/OCR text, and web pages into a reviewable draft |
| Nutrition | `Nutrition/` | USDA FoodData Central client, gram estimation from volumes and counts, per-recipe report with confidence |
| Search | `Search/` | `SearchQuery` (chips, merging), `SearchEngine` (local predicate, relaxation), keyword and fallback interpreters |
| Profile | `DietaryProfile` | Presets, custom exclusions, the disclaimer copy |

## App layer

| Area | Files | Responsibility |
|---|---|---|
| Entry | `ProportionApp`, `RootView` | Model container (CloudKit with local fallback), tab structure, pending-import hand-off |
| Persistence | `Model/StoredRecipe` | `@Model` wrapper storing the recipe as JSON with denormalised fields for sorting; CloudKit-compatible schema |
| Settings | `Model/SettingsStore` | Units, dietary profile, targets, the model privacy switch |
| Import | `Services/RecipeImporter`, `OCRService` | Orchestrates every capture path: exact data → deterministic parse → model, gated by the privacy setting |
| Model access | `Services/ClaudeClient` and adapters | Raw Messages API over URLSession; one strict tool call per request |
| Views | `Views/` | Library, detail, editor (review / manual / edit), search, capture, settings |
| Extension | `ProportionShare/`, `Shared/PendingImport` | Receives URLs, text and images; hands them to the app through the App Group |

## Design decisions

**Quantities are exact rationals.** `2 cups` at 7 servings is exactly
`7/2 cup`, and every scale operation starts from the base recipe, so repeated
adjustment cannot drift. Display rounding (⅛ cup, ¼ tsp, 5 g under 100 g,
25 g above) is recomputed from the exact value each time; clean fractions the
recipe already uses (⅓ cup) are preserved; tiny amounts never collapse to zero.

**Units convert exactly within a family, approximately across.** Teaspoons,
tablespoons and cups form one family (3 / 48 tsp); grams and kilograms
another. Cups → millilitres is a display-time conversion and never touches
stored data.

**Per-serving macros are invariant under scaling.** They are read from the
base recipe rather than divided back out of scaled totals, so they cannot
disagree with themselves.

**The model interprets; it never selects.** Conversational search sends one
message to the model with one job — produce a `SearchQuery` — and the query
runs as a local predicate over the library. It cannot invent a recipe, it is
instant, and it works offline through the keyword interpreter.

**Deterministic before probabilistic, everywhere.** JSON-LD before text
extraction, the line parser before the model, on-device OCR before vision. The
model is the fallback for what a regex cannot do, and it is gated by a privacy
switch in Settings. Every draft passes through the review screen before it is
saved.

**Exclusions walk a taxonomy and are over-inclusive on purpose.** "No dairy"
catches parmesan, ghee and buttermilk; "no butter" does not catch peanut
butter. A filter that occasionally hides a fine recipe is a nuisance; one that
shows an unsafe one is a harm — which is why the UI never uses the words
"safe" or "free from", and the dietary profile carries a disclaimer wherever
it is edited.

**Social video is handled through the share sheet.** Downloading TikTok or
Instagram content violates their terms and fails App Store review. The Share
Extension takes the caption the host app provides — which is usually where the
recipe is — together with any JSON-LD on the linked page.

**Persistence stores the recipe as a blob.** `StoredRecipe` keeps the whole
`Recipe` as JSON plus a few denormalised fields for sorting. This keeps the
SwiftData schema trivially CloudKit-compatible and lets the core's value types
evolve without migrations.

## Model usage

Requests go to the Messages API (`claude-opus-5` by default, configurable in
`App/Config/Base.xcconfig`) with adaptive thinking, a per-call effort level,
prompt caching on the system prompt, and server-side refusal fallbacks
enabled. Each call defines exactly one tool with a strict JSON schema and
decodes the resulting tool input; there is no free-text parsing of model
output.

## Verification status

| Layer | How it is verified |
|---|---|
| `ProportionCore` | 170 unit tests, run on Linux and macOS in CI and on Windows locally |
| App build | Warning-free `xcodebuild` for the simulator on every push |
| App behaviour | UI test walkthrough of every screen in the simulator (light, dark, accessibility text size) with screenshots and a recording published as artifacts |
| Device features | **Not yet verified.** Camera capture, the Share Extension from a real social app, and iCloud sync need a physical iPhone |
