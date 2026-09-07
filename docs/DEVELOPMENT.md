# Development guide

## Prerequisites

- macOS with Xcode 16 or later for the app
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the Xcode project is
  generated from `App/project.yml` and is not committed
- Any Swift 5.9+ toolchain for the core package alone

## Building the app

```bash
brew install xcodegen
cd App
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # optional
xcodegen generate
open Proportion.xcodeproj
```

Set your team under Signing & Capabilities. The app uses three identifiers
defined in `project.yml`; change the `com.proportion` prefix if you need your
own:

| Identifier | Used for |
|---|---|
| `com.proportion.app` | App bundle |
| `iCloud.com.proportion.app` | CloudKit container for sync |
| `group.com.proportion.app` | App Group shared with the Share Extension |

### Secrets

`App/Config/Base.xcconfig` optionally includes `Secrets.xcconfig`, which is
git-ignored. Values flow into `Info.plist` at build time and are read by
`Secrets.swift`; an empty or placeholder value reads as "not configured" and
the corresponding feature degrades gracefully.

## Running the core tests

```bash
cd ProportionCore
swift test
```

### On Windows

Swift on Windows links against MSVC's C runtime, so the toolchain must run
inside a Visual Studio developer environment. Install once:

```powershell
winget install Swift.Toolchain
winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

Then run the script, which sets up `vcvars64` and the toolchain path before
calling `swift test`:

```powershell
powershell -File scripts\test-core.ps1
```

## Continuous integration

`.github/workflows/ci.yml` runs three jobs on every push to `main` and on
pull requests:

| Job | Runner | What it does |
|---|---|---|
| Core tests (Linux) | `ubuntu-latest` | `swift test` for `ProportionCore` |
| iOS app build | `macos-15` | Core tests on macOS, then a simulator build of the app and Share Extension. Fails on any error; the full log is uploaded |
| Simulator screenshots | `macos-15` | Boots an iPhone 16 Pro simulator, runs the UI tests, exports screenshots and a screen recording |

### Screenshot pipeline

The `ProportionUITests` target walks every screen and attaches a screenshot at
each stop — the light-mode walkthrough, a dark-mode pass, and an accessibility
text-size pass. CI exports the attachments from the result bundle and uploads
them as the `screenshots` artifact (named files plus `manifest.json`), with the
recording as `walkthrough-video`.

To review a run from any machine:

```bash
gh run list --branch main --limit 1
gh run download <run-id> -n screenshots -D ./screens
```

The app supports these launch arguments for testing:

| Argument | Effect |
|---|---|
| `-ui-testing` | In-memory store seeded with `SampleData.recipes`; CloudKit checks skipped |
| `-ui-testing-dark` / `-ui-testing-light` | Force the colour scheme |
| `-UIPreferredContentSizeCategoryName <category>` | Standard iOS Dynamic Type override |

Accessibility identifiers used by the tests: `recipe-card`,
`servings-increment`, `servings-decrement`, `search-input`, `search-send`,
`editor-cancel`. Toolbar buttons are found by label.

## Conventions

- Logic goes in `ProportionCore` with a test; views stay declarative.
- `Recipe` and its parts are value types; `StoredRecipe` is the only `@Model`.
- Every capture path produces a `RecipeDraft` and ends on the review screen.
- Model-backed features must degrade to a deterministic fallback when the key
  is absent, the privacy switch is off, or the network is unavailable.
- Copy never describes dietary filtering as "safe" or "free from".
