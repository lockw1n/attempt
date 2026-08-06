# Attempt

A SwiftUI app for iOS.

## Requirements

| | |
|---|---|
| Xcode | 26.6 (build 17F113) |
| Swift | 6.3 toolchain, Swift 6 language mode everywhere — packages and app target |
| Deployment target | iOS 26.5 |
| Bundle identifier | `lockw1n.Attempt` |

## Getting started

```bash
open Attempt.xcodeproj
```

Pick a simulator and press ⌘R. No special flags are needed. From the command line:

```bash
xcodebuild build -project Attempt.xcodeproj -scheme Attempt -destination 'generic/platform=iOS Simulator'
```

## Project structure

Domain and infrastructure live in local Swift packages. The app target is a
composition root — entry point and dependency wiring, nothing else.

```
Packages/
├── PowerliftingCore/        Pure Swift domain layer: value types, formulas, resolvers
├── Persistence/             SwiftData models, schema versioning, repositories
└── DesignSystem/            Tokens, components, theme (empty until Phase 1)
Attempt/
├── App/                     App entry point and DI wiring
├── Resources/               String catalogs, fonts, data files
└── Assets.xcassets          Colors, images, app icon
```

Dependencies run one way: `Persistence` may import `PowerliftingCore`, never the
reverse, and the app may import all three. Two constraints are load-bearing
rather than stylistic:

- **`PowerliftingCore` imports nothing at all** — not `Foundation`, not `SwiftUI`,
  and not the platform modules (`Darwin`, `Glibc`) either. Enforced by the `linux`
  CI job together with the `no_foundation_in_core` and `no_imports_in_core` lint
  rules. One consequence to know before you hit it: `pow` and `exp` are
  unavailable, so use `RealMath.swift` rather than reaching for an import.
- **Only `Persistence` imports `SwiftData`.** Everything else reaches storage
  through repository protocols that expose value types and DTOs.

All three packages are linked into the app target as local package references, so
`xcodebuild` builds them alongside the app. The project uses **file-system
synchronized groups**: the folder tree on disk *is* the project structure, and
adding or removing a file does not churn `.pbxproj`.

## Building and testing

Build every package with warnings treated as errors:

```bash
./scripts/build-packages.sh --test
```

There is no root package, so a bare `swift build` at the repo root fails; pass a
path to work on one in isolation (`./scripts/build-packages.sh Packages/PowerliftingCore`).
Note that a bare `swift build` does **not** fail on warnings — that gate lives in
the script, not in the manifests.

`PowerliftingCore` and `Persistence` each have a Swift Testing target (`@Test` /
`#expect`, not XCTest). The app target has no tests; it is a composition root
with an empty scene.

```bash
swift test --package-path Packages/PowerliftingCore
swift test --package-path Packages/Persistence
```

`PowerliftingCoreTests` is held to the same no-Apple-frameworks rule as the module
it tests, and runs on the Linux job too. In particular `Codable` is asserted
through the hand-rolled `Encoder`/`Decoder` in
`Tests/PowerliftingCoreTests/CodableProbe*.swift`, never `JSONEncoder`.

`PowerliftingCore` is held to ≥ 90% line coverage. The script counts only files
under the package's `Sources/`, and requires `python3`:

```bash
./scripts/coverage.sh --threshold 90
```

Two CI assertions that also run locally — the first guards the app target's Swift
build settings, the second the `@unchecked Sendable` justifications:

```bash
./scripts/audit-app-build-settings.sh
./scripts/audit-unchecked-sendable.sh
```

## Conventions

**Concurrency.** Packages build with `.defaultIsolation(nil)`, so declarations are
`nonisolated` unless they say otherwise and the domain layer stays
actor-agnostic. The app target is the deliberate exception:
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Note that `public` types get no
implicit `Sendable` synthesis — write the conformance. `@unchecked Sendable`
needs `Sendable justification: <why>` on the same line or directly above the
declaration; a blank line between the two breaks the association and fails the
audit.

**Warnings are errors.** The app target sets `SWIFT_TREAT_WARNINGS_AS_ERRORS`;
the packages get it from `scripts/swift-strict-flags.sh` via
`build-packages.sh`, which globs `Packages/*/Package.swift` so a new package is
covered the moment it exists.

**Domain rules.** These are storage contracts — breaking one is a migration, not
a refactor.

- Weights are `Int` grams. Use `Weight` for every weight-bearing value;
  kilograms and pounds are display concerns only. It is signed, because it also
  expresses a delta.
- A logged weight is the load on **one** implement: two 40 kg dumbbells is 40,
  not 80.
- Domain enums are `String`-backed, never ordinal, so reordering cases is free
  and renaming one is a migration. What an unrecognised value does — degrade,
  preserve, or throw — is decided per type and documented on that type.
- `Codable` domain types hand-write `init(from:)`, `encode(to:)` and their
  `CodingKeys`, and pin key spelling *and* key order by assertion.
- A domain collection is canonicalised — sorted, and either deduplicated or, where
  a repeat is a data-entry error rather than noise, refused outright — both on
  construction and on decode.
- Derived values (e1RM, personal records, training maxes) are recomputed, never
  stored as truth. Cached copies carry a `computationVersion`.
- Deletion is soft (`deletedAt`); hard deletion happens only through an explicit
  purge routine.

**Strings.** User-facing text goes through `String(localized:)` and lands in
`Resources/Localizable.xcstrings`.

**Commits carry requirement IDs.** Lead the subject with the requirement the work
traces to, then a colon:

```
TR-0.2.1: add Weight value type
G-6.4, TR-0.1.3: enable strict concurrency across the packages
```

IDs are `G-*`, `FR-*`, `NFR-*`, `TR-*`, `OUT-*`, `DOD-*` and `D-*`;
comma-separate when a commit covers more than one. This keeps
`git log --grep TR-0.2` meaningful and cannot be backfilled once a commit is
pushed. Work that traces to no requirement is scope creep — resolve that rather
than inventing an ID. An optional hook warns on a missing ID and never blocks:

```bash
git config core.hooksPath scripts/git-hooks
```

Pull requests use `.github/pull_request_template.md`. The requirement IDs
themselves are defined in `docs/`, which is deliberately **not committed** — so a
reference like `TR-0.2.2` is a stable label rather than a link if you are reading
this without it.

## Linting and formatting

```bash
brew install swiftlint
swiftlint lint --strict
```

`swift format` ships with the toolchain. Config is `.swift-format`: 4-space
indentation and a 120-column limit, matching `.editorconfig` and SwiftLint's
`line_length` rather than the tool's own defaults.

```bash
swift format lint --strict --recursive Attempt Packages
swift format --in-place --recursive Attempt Packages
```

**`--strict` is not optional.** Without it `swift format lint` prints violations
as warnings and still exits 0, so a check that omits it is decorative.

Six custom rules beyond the standard set, in `.swiftlint.yml` under
`custom_rules`:

| Rule | Enforces |
|---|---|
| `no_color_literals` | `G-7.7` — colour tokens, not literals |
| `no_raw_font_sizes` | `G-7.7` — typography tokens, not point sizes |
| `no_magic_spacing` | `G-7.7` — spacing tokens, not numbers |
| `no_swiftdata_outside_persistence` | `TR-0.1.2` — only `Persistence` imports SwiftData |
| `no_foundation_in_core` | `NFR-0.2` — `PowerliftingCore` is Foundation-free |
| `no_imports_in_core` | `NFR-0.2` — `PowerliftingCore/Sources` imports nothing |

Each is verified against a fixture that violates it on purpose. Run this after
touching any rule — a broken regex or a path filter that matches nothing leaves
`swiftlint lint` green while enforcing nothing:

```bash
./scripts/verify-lint-rules.sh
```

To lint on every build, add a **Run Script** build phase to the `Attempt` target
with `if which swiftlint > /dev/null; then swiftlint; fi`, and untick "Based on
dependency analysis".

## CI

`.github/workflows/ci.yml` runs on every push and pull request to `main`:

| Job | What it does |
|---|---|
| **Build** | audits the app target's build settings, then builds the app |
| **Package tests** | both suites with coverage, all packages with warnings as errors, the warnings-gate proof, the `@unchecked Sendable` audit |
| **Linux core build** | builds and tests `PowerliftingCore` on `ubuntu-latest` in a Swift container |
| **SwiftLint** | lint, custom-rule verification, format check |

All four are **required checks on `main`**, so a red run blocks the merge. The
whole workflow takes about a minute.

The `linux` job covers `PowerliftingCore` only — `Persistence` and `DesignSystem`
are Apple-only by design. Its container tag is pinned to an exact patch version;
bump it on its own.

Two things to know before editing the workflow. A required check is matched by
its **display name**, so renaming a job silently drops it from the protection
rule — the old name stays listed and never reports again. And a **newly added**
job is unprotected until its first run, because GitHub cannot mark a check
required until it has reported once.
