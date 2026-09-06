# Proportion

A macro-first recipe manager for iPhone. Capture a recipe from a photo, a
link, pasted text, or the share sheet; get structured ingredients and
macronutrients; re-scale it to any serving count with ingredients and
nutrition recalculating together; and find what to cook by describing it —
"high protein dinner, no dairy, under 30 minutes".

The product spec is [docs/SPEC.md](docs/SPEC.md).

## Status

| Stage (from the spec's build order) | State |
|---|---|
| 1. Data model + scaling engine | ✅ Implemented, **170 tests passing** |
| 2. Manual entry, library, recipe detail | ✅ Implemented (SwiftUI, not yet compiled — see below) |
| 3. Ingredient taxonomy + filter chips | ✅ Implemented and tested |
| 4. Paste-text / link parsing | ✅ JSON-LD, plain-text and HTML parsers tested; Claude parser implemented |
| 5. Nutrition lookup | ✅ USDA client + gram estimation + calculator tested; Claude estimator implemented |
| 6. Conversational search | ✅ Query model, local engine, keyword interpreter tested; Claude interpreter implemented |
| 7. Dietary profile | ✅ Implemented and tested |
| 8. Photo / OCR capture | ✅ Implemented (Vision framework) |
| 9. Share Extension | ✅ Implemented (App Group hand-off) |
| 10. CloudKit sync | ✅ Configured (SwiftData + private database, local fallback) |

**What has been verified:** everything in `ProportionCore/` — the engine that
holds all of the logic — builds and passes its test suite. It was developed
and run on Windows with the swift.org toolchain, so it is known to be
Foundation-only and portable.

**What has not:** the SwiftUI/SwiftData app layer in `App/` was written on a
machine without Xcode and has not been compiled. Expect a first Xcode build to
surface a handful of small issues (a modifier signature, a strict-concurrency
warning). The architecture keeps that layer thin on purpose: views call into
`ProportionCore`, and every parser, matcher and calculator lives where it can
be tested.

## Layout

```
proportion/
├── docs/SPEC.md                    Product spec and build order
├── scripts/test-core.ps1           Runs the core tests on Windows
├── ProportionCore/                 Pure-Swift engine — Foundation only
│   ├── Sources/ProportionCore/
│   │   ├── Rational.swift              Exact fractions: no float drift, ever
│   │   ├── Units.swift                 Unit families; exact conversion inside a family only
│   │   ├── Quantity.swift              amount + unit — the stored form of every amount
│   │   ├── Macros.swift                protein / fat / carbs; calories derived (4/4/9)
│   │   ├── Ingredient.swift, Recipe.swift
│   │   ├── ScalingEngine.swift         Non-destructive scaling by servings or protein
│   │   ├── QuantityFormatter.swift     Unit promotion/demotion, cook-friendly rounding
│   │   ├── IngredientTaxonomy.swift    parmesan → hard cheese → cheese → dairy
│   │   ├── TaxonomyData.swift          The bundled hierarchy (~400 terms)
│   │   ├── IngredientLineParser.swift  "2 cups flour, sifted" → structured, deterministic
│   │   ├── PlainTextRecipeParser.swift Pasted / OCR text → draft, deterministic
│   │   ├── JSONLDRecipeExtractor.swift schema.org Recipe from a web page
│   │   ├── HTMLTextExtractor.swift     Readable lines from a page with no JSON-LD
│   │   ├── RecipeDraft.swift           What every capture path produces for review
│   │   ├── DietaryProfile.swift        Presets + custom exclusions; the disclaimer
│   │   ├── Nutrition/                  USDA client, gram estimation, calculator
│   │   └── Search/                     SearchQuery, SearchEngine, keyword + fallback interpreters
│   └── Tests/ProportionCoreTests/      170 tests
└── App/                            iOS app (Xcode 16, iOS 18)
    ├── project.yml                     XcodeGen definition — generates the .xcodeproj
    ├── Config/                         Base.xcconfig + Secrets.example.xcconfig
    ├── Shared/PendingImport.swift      App Group hand-off used by app and extension
    ├── Proportion/
    │   ├── ProportionApp.swift         Entry point; SwiftData + CloudKit container
    │   ├── Model/                      StoredRecipe (@Model), SettingsStore, PendingImportsController
    │   ├── Services/                   ClaudeClient, Claude adapters, RecipeImporter, OCRService, AppServices
    │   └── Views/                      Library, Detail, Editor (review/manual/edit), Search, Capture, Settings
    └── ProportionShare/                Share Extension
```

## Building the app

1. On a Mac with Xcode 16+:
   ```bash
   brew install xcodegen
   cd App
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # add your keys
   xcodegen generate
   open Proportion.xcodeproj
   ```
2. Set your team for signing. The bundle IDs, iCloud container
   (`iCloud.com.proportion.app`) and App Group (`group.com.proportion.app`)
   are in `project.yml`; change the prefix if you prefer.
3. Keys are optional. With no Anthropic key the app uses its deterministic
   parsers and keyword search only; with no USDA key nutrition stays whatever
   the source provided, honestly labelled.

Model calls use `claude-opus-5` via the Messages API with adaptive thinking and
server-side refusal fallbacks enabled (`fallbacks: "default"`); the model name
is set in `Config/Base.xcconfig`.

## Running the core tests

Any platform with a Swift 5.9+ toolchain:

```bash
cd ProportionCore
swift test
```

On Windows, the toolchain needs MSVC's C runtime to link, so use the script,
which sets up the Visual Studio environment first:

```powershell
powershell -File scripts\test-core.ps1
```

## Design decisions worth knowing

**Quantities are exact rationals.** `2 cups` at 7 servings is exactly
`7/2 cup`, and every scale operation starts from the base recipe, so hammering
the serving stepper can never drift. Display rounding (⅛ cup, ¼ tsp, 5 g under
100 g, 25 g above) is recomputed from the exact value each time; clean
fractions the recipe already uses (⅓ cup) are preserved; tiny amounts never
collapse to zero.

**Per-serving macros are structurally invariant under scaling.** They are read
from the base recipe, never divided back out of scaled totals, so they cannot
disagree with themselves.

**The model interprets; it never selects.** Conversational search sends one
message to the model with one job — produce a `SearchQuery` — and the query
runs as a local predicate over the library. It can't hallucinate a recipe,
it's instant, and it works offline through the keyword interpreter.

**Deterministic before probabilistic, everywhere.** JSON-LD before text
extraction, the line parser before the model, on-device OCR before vision. The
model is the fallback for what a regex can't do, and it's gated by a privacy
switch in Settings.

**Exclusions walk a taxonomy and are over-inclusive on purpose.** "No dairy"
catches parmesan, ghee and buttermilk; "no butter" does *not* catch peanut
butter. A filter that occasionally hides a fine recipe is a nuisance; one that
shows an unsafe one is a harm — which is also why the UI never uses the words
"safe" or "free from".

**Social video is handled through the share sheet.** Downloading TikTok or
Instagram content violates their terms and fails App Store review, so the
Share Extension takes the caption the host app provides — which is where the
recipe usually is — and the page's JSON-LD when there is any.
