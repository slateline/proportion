# Build: Macro-First Recipe Manager (iOS)

## Goal
A native iPhone app that captures recipes from anywhere, extracts structured
ingredients and macronutrients, and lets the user re-scale any recipe by serving
count with ingredients and nutrition recalculating together. Saved recipes are
retrieved through a conversational search that understands what the user wants
to eat and what they want to avoid.

Macros (protein / fat / carbs) are the organizing principle of the entire UI —
not a detail buried on a sub-screen. Every recipe card, list row, and detail
view leads with them.

## Stack
- Swift 6 + SwiftUI, iOS 18 minimum, iPhone only (portrait primary)
- SwiftData for local persistence; app must be fully functional offline for
  saved recipes
- CloudKit private database for cross-device sync (no account system, no
  server of your own)
- One LLM call path for parsing and query understanding (Claude API or
  equivalent), keyed via a config file — never hardcode the key
- VisionKit / Live Text for on-device OCR before anything is sent to a model

## Capture flows (build all four)

1. **Photo import** — user photographs a cookbook page, handwritten card, or
   screenshot. Run on-device OCR first, send the extracted text (not the image)
   to the parser when OCR confidence is adequate; fall back to vision input
   when it isn't.

2. **Share Extension** — the primary flow. User taps Share in Safari,
   Instagram, TikTok, or YouTube and picks this app. You receive a URL and
   whatever text the host app provides.
   - For web URLs: fetch the page, prefer JSON-LD `Recipe` schema.org markup
     when present (most recipe sites have it — this is far more reliable than
     LLM parsing), fall back to readability extraction + LLM parse.
   - For social URLs: do NOT attempt to download or scrape video content —
     it violates platform ToS and will fail App Store review. Instead, use the
     shared caption/description text, plus oEmbed metadata where the platform
     offers it publicly. If that yields too little, present a "paste the
     recipe text or add screenshots" fallback rather than failing silently.

3. **Paste text** — a plain textarea. The universal escape hatch.

4. **Manual entry** — structured form. Always available; also the edit surface
   for correcting a bad parse.

## Parsing contract
The parser returns a strict JSON structure. Reject and retry once on schema
violation, then fall back to manual entry with whatever was extracted
pre-filled.

Each ingredient must be stored **structured, never as a display string**:
quantity (as a rational number, not a float), unit, canonical item name,
preparation note ("finely diced"), a resolved gram weight, and a
`scalable: true|false` flag. Display strings are always rendered from these
fields, never parsed back out of them.

Also capture: title, source URL/attribution, base serving count, prep and cook
time, step list, and a parse-confidence score.

## Ingredient taxonomy
Every ingredient resolves to a canonical name plus a set of category tags
walking up a hierarchy — `parmesan` → `hard cheese` → `dairy`; `peanut butter`
→ `peanut` → `legume`, `nut-adjacent`. Maintain this as a bundled local
dataset, not an LLM call at query time.

This taxonomy is what makes exclusion search work. Naive string matching fails
in exactly the cases that matter most: excluding "dairy" must catch butter,
cream, and parmesan; excluding "peanut" must catch peanut butter, groundnut,
and satay sauce. Build the taxonomy before the search feature that depends
on it.

## Nutrition engine
- Resolve each ingredient to a gram weight, then look it up against USDA
  FoodData Central (free API) and sum the totals
- Where an ingredient cannot be resolved, fall back to an LLM estimate and
  mark that ingredient with a visible "estimated" indicator
- Show a recipe-level confidence state: Verified / Partially estimated /
  Estimated
- Display per-serving and whole-recipe totals, plus calories derived from
  macros (4/4/9)
- Persistent disclaimer that values are approximate and not medical advice

## Scaling engine — get this right, it's the core feature
Scale factor = target servings ÷ base servings. Servings adjustable from 1 to
50, and the user may also scale by entering a target protein amount.

- Scale the rational quantity, never a rounded display value — repeated
  adjustments must not accumulate drift
- Re-render to cook-friendly fractions: nearest 1/8 for cups, 1/4 for tsp/tbsp,
  5g for weights under 100g, 25g above
- Promote and demote units at thresholds: 3 tsp → 1 tbsp, 16 tbsp → 1 cup,
  1000g → 1kg
- Pass through non-numeric quantities unchanged: "to taste", "a pinch",
  "1 pan", "salt for the water"
- Mark items that don't scale linearly (leavening, spices, baking times, pan
  size) with `scalable: false` — still scale them, but surface an inline note:
  "Seasoning may need adjusting by taste"
- Per-serving macros stay constant as servings change; whole-recipe totals
  scale. Make this visually obvious so it doesn't read as a bug.
- Scaling is non-destructive: the base recipe is never overwritten

## Conversational search
A chat-style interface for finding recipes in natural language: "high protein
dinner, no dairy, under 30 minutes", "something with the chicken thighs I have,
but I'm sick of rice".

**How it works.** The message is sent to the LLM with one job only: convert it
into a structured query object — include ingredients, exclude ingredients,
macro ranges, max time, tags, meal type. That structured query then runs as a
local predicate against SwiftData. The model interprets intent; it does not
select the results. This keeps search fast, offline-capable after the parse,
and impossible to hallucinate.

**Show the interpretation.** Render the parsed query as editable chips above
the results — `protein ≥ 30g`, `excludes: dairy`, `≤ 30 min`. The user must be
able to see that "high protein" became a specific threshold and tap to change
it. A conversational search that silently guesses wrong is worse than a filter
form.

**Refine, don't restart.** Follow-up messages mutate the existing query.
"Actually no chicken either" adds an exclusion and keeps everything else. Show
the query evolving in the chips. Include a clear reset.

**Never invent recipes.** Results come from the saved library. If the app also
suggests recipes the user hasn't saved, they go in a visually separate section
labelled as suggestions with no macro data claimed until imported. A generated
recipe must never be indistinguishable from a saved one.

**Handle zero results well.** Name the constraint that eliminated everything
("nothing under 20 minutes — the closest is 35"), and offer to relax it with
one tap. Never return an empty screen.

**Offline and fallback.** Query parsing needs the network. When it's
unavailable, degrade to the same filter chips driven manually — search must
never be fully blocked.

## Dietary profile
"Foods to avoid" splits into two different things and the app must treat them
differently:

- **Persistent exclusions** — allergies and hard dietary rules, set once in
  Settings, applied to every search and shown as a locked chip the user can
  see but not accidentally clear. Allergies don't change per query.
- **Per-query exclusions** — "not in the mood for fish tonight", set in chat,
  cleared on reset.

Recipes violating a persistent exclusion are hidden by default with a "3 hidden
by your dietary profile" affordance to reveal them deliberately.

**Critical:** never present this as allergen safety. The exclusion list filters
on parsed ingredient text, which can be incomplete or wrong, and it knows
nothing about cross-contamination or "may contain" manufacturing. Label it a
convenience filter, state plainly in Settings that it is not a substitute for
reading labels, and never use the words "safe" or "free from" in the UI.

## Screens
- **Library** — searchable, sortable grid of saved recipes. Filter by macro
  range, tag, and cook time. Conversational search is the primary entry point
  at the top; manual filters remain available and stay in sync with the chips.
- **Search** — chat transcript, parsed-query chips, results inline as recipe
  cards
- **Recipe detail** — hero image, macro ring/bar chart, serving stepper pinned
  and always visible, ingredients, steps, source attribution
- **Capture** — the four flows above behind one clear entry point
- **Parse review** — mandatory confirmation screen before saving. Show what
  was extracted, flag low-confidence fields, make everything editable inline.
  Never save a parse the user hasn't seen.
- **Settings** — units (metric/imperial), dietary profile and persistent
  exclusions, optional daily macro targets, sync status, data export

## Design direction
Clean and editorial, closer to a well-made cooking magazine than a fitness
tracker. System fonts with a tight type scale, generous whitespace, one
restrained accent color, food photography allowed to carry the visual weight.
Full Dark Mode. Dynamic Type support up to accessibility sizes without layout
breakage. VoiceOver labels on every control. Haptics on the serving stepper.

## Required behaviors
- Every network operation has explicit loading, empty, error, and offline states
- Parsing failures degrade to manual entry with partial data preserved —
  never a dead end
- Recipe data exportable as JSON
- No analytics, no account, no data leaving the device except parser calls
  and CloudKit sync — state this plainly in Settings

## Out of scope for v1
Meal planning, grocery lists, barcode scanning, social features, Apple Health
integration, Android, iPad-optimized layouts.

## Build order
1. Data model + scaling engine, with unit tests covering fraction rendering,
   unit promotion, non-scaling passthrough, and drift across repeated scaling
2. Manual entry + library + recipe detail (a complete working app with zero AI)
3. Ingredient taxonomy + manual filter chips (deterministic, testable)
4. Paste-text parsing
5. Nutrition lookup
6. Conversational search layered over the working filter chips
7. Dietary profile + persistent exclusions
8. Photo/OCR capture
9. Share Extension
10. CloudKit sync

Ship each stage working before starting the next.
