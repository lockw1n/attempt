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
├── RepositoryInterface/     The storage boundary: repository protocols, records, wire format
├── Persistence/             SwiftData models, schema versioning, repositories
├── RepositoryFakes/         In-memory repositories, and the conformance suite both must pass
├── SeedContent/             The seed payload's schema and its validator, plus SCHEMA.md
├── SeedImport/              Merges the seed catalogue into the exercise repository
├── RemoteContent/           formulas.json/flags.json's schema, validator and generator, plus SCHEMA.md
├── RemoteFetch/             Fetches, caches and falls back for the three published payloads
├── DesignSystem/            Two targets: DesignTokens (spacing, type, colour scales) and
│                            DesignSystem (components, built from the tokens — still empty)
└── DebugHarness/            Throwaway end-to-end run: seeds, logs a set, prints PRs and e1RM
Attempt/
├── App/                     App entry point and DI wiring
├── Resources/               String catalogs, fonts, data files
└── Assets.xcassets          Colors, images, app icon
```

Dependencies run one way: `Persistence` → `RepositoryInterface` → `PowerliftingCore`,
never back, and the app may import any of them. `RepositoryFakes` sits beside
`Persistence` rather than under it: its library depends on `RepositoryInterface`
alone, and only its test target depends on `Persistence`, because the conformance
suite there has to name both implementations. `SeedContent` sits off to one side:
it depends on `PowerliftingCore` alone. `SeedImport` sits above both `SeedContent`
and `RepositoryInterface`, since neither of those may depend on the other, and is
the only package that names both. `RemoteContent` sits beside `SeedContent`,
depending on `PowerliftingCore` alone for the same reason: a content contract
must not be shaped like a storage record. `RemoteFetch` sits above both
`RemoteContent` and `SeedContent`, for the same reason `SeedImport` sits above
`SeedContent` and `RepositoryInterface` — it is the one place that names both,
because the bundled leg of `exercises.json`'s fallback lives in `SeedContent`.
Two constraints are load-bearing rather than stylistic:

- **`PowerliftingCore` imports nothing at all** — not `Foundation`, not `SwiftUI`,
  and not the platform modules (`Darwin`, `Glibc`) either. Enforced by the `linux`
  CI job together with the `no_foundation_in_core` and `no_imports_in_core` lint
  rules, which are scoped by path and so cover that package's **tests** as well as
  its sources. Two consequences to know before you hit them: `pow` and `exp` are
  unavailable, so use `RealMath.swift` rather than reaching for an import; and code
  that needs Foundation to test the domain layer belongs in another package, which
  is why `SeedContent` is one.
- **Only `Persistence` imports `SwiftData`.** Everything else reaches storage
  through the protocols in `RepositoryInterface`, which expose value types and
  record types and depend on nothing below them — so a `@Model` is not nameable
  there even by accident, and entities are `internal` besides. That package is
  built on the `linux` job for this reason: SwiftData does not exist there, where
  on Darwin every target can import it. The conventions every entity carries —
  identity, timestamps, soft delete — are on the `StoredEntity` protocol, and the
  four rules every repository shares are in `RepositoryInterface.swift`. Both are
  where to look before adding an entity or a method.

A record is a value type mirroring one stored row, column for column. It is
`Codable` — that is a requirement of the `StoredRecord` protocol — and the format's
shared rules are in `RecordCoding.swift`. A record validates nothing; the four
places a row is refused on account of what it says are the projections in
`Projections.swift`. Mapping between an entity and its record lives in
`Packages/Persistence/Sources/Persistence/Mapping/`, which is the only place the
two are named in one file.

`PersistenceStack` is how you get a store. It opens one container and hands back
the five repositories as existentials:

```swift
let stack = try PersistenceStack(location: .inMemory)   // or .applicationDefault, .file(url)
let exercises = try await stack.exercises.exercises(includingDeleted: false)
```

It is the only public type in `Persistence`. The five implementations and the
`ModelContainer` are `internal`, so nothing outside the module can name a
SwiftData-backed type. Repository reads and writes live in
`Packages/Persistence/Sources/Persistence/Repositories/`; start with
`RowResolution.swift`, which carries the one shape every read has and the reason it
is not a `FetchDescriptor`.

`InMemoryRepositoryStack()` is the same five repositories without a store file, for
previews and for tests of code that consumes them:

```swift
let stack = InMemoryRepositoryStack()
```

It is the only public type in `RepositoryFakes`, for the reason `PersistenceStack`
is the only public type in `Persistence`. The two are held to one suite: the
conformance tests in `Packages/RepositoryFakes/Tests/` are parameterized over both
stacks and so run twice, once per implementation. That suite's header says what is
in its scope and what is not. The handful of tests beside them covering the fakes'
own machinery run once.

`SeedContent` holds the shape of `exercises.json` — the catalogue bundled with the
app and published to the content endpoint — and the validator that gates it:

```swift
let failures = SeedCatalogueValidator.validate(try Data(contentsOf: url), minimumExercises: 80)
```

An empty result is the only passing result; every failure names the entry it is in.
`Packages/SeedContent/SCHEMA.md` documents the document, and is the file to read
before authoring or editing a catalogue. Two things to know before adding to it: the
payload is not a storage record and carries no audit columns, and the four
vocabularies are never restated — the validator resolves through
`PowerliftingCore`'s enums, so a spelling is checked with `init?(rawValue:)` rather
than by decoding, which would resolve an unknown value to `other` instead of
refusing it.

`SeedImport` merges a validated catalogue into `ExerciseRepository`:

```swift
let summary = try await SeedImporter(exercises: stack.exercises).importBundledCatalogue()
```

A second run over the same catalogue performs no writes at all — each entry is
compared against the stored row and saved only when the columns the seed owns have
moved. It reads the app bundle and never the network, which
`no_networking_in_seed_import` enforces by lint rather than by test, and its own
module header names which columns a re-import may overwrite and which belong to
the row.

`RemoteContent` holds the schema and validator for the other two content
endpoints — `formulas.json` and `flags.json`, which unlike `exercises.json` have
no bundled counterpart:

```swift
let failures = RemoteFormulasValidator.validate(try Data(contentsOf: formulasURL))
```

`Packages/RemoteContent/SCHEMA.md` documents both payloads.
`PublishedContent` is the one home for the base URL, the three payloads' paths
under it, and the encoder that produces their bytes.
`scripts/generate-remote-content.sh` builds all three: it copies `exercises.json`
verbatim and runs the package's own `GenerateRemoteContent` executable to encode
`formulas.json` and `flags.json` fresh — validating all three, the copy
included, before writing any of them, so the run fails rather than publish a
payload any of the three validators would refuse. `.github/workflows/deploy-content.yml`
runs that script on every push to `main` touching these sources and publishes
the result to GitHub Pages, at `PublishedContent.baseURL`.

`RemoteFetch` is what an app actually calls: `ContentFetcher.resolve(_:)` answers
synchronously from whatever is already cached or bundled, and `refresh(_:)` is
the async half that fetches, validates and caches a newer edition without ever
throwing:

```swift
let fetcher = ContentFetcher(transport: URLSessionTransport(), cache: ContentCache(directory: url))
let current = fetcher.resolve(.formulas)          // never touches the network
_ = await fetcher.refresh(.formulas)               // updates the cache for next time
```

`fetcher.upgradeDecision(runningVersion:)` reads the resolved `flags.json`'s minimum-supported-version
against the running build and returns `.allowed`, `.blocked`, or `.allowedByDefault(FailOpenReason)`
for anything unreadable — see `UpgradeGate` in `RemoteFetch`.

`DebugHarness` seeds the bundled catalogue, logs a short training history, and prints the personal
records and e1RM that come back out:

```bash
swift run --package-path Packages/DebugHarness attempt-harness
```

It publishes an executable product only, so the app target cannot link it — that is the whole of
how it stays out of release builds, checked by `scripts/check-harness-excluded.sh`.

`PowerliftingCore`, `Persistence` and `DesignSystem` are linked into the app
target as local package references, so `xcodebuild` builds them alongside the app.
`RepositoryInterface` arrives transitively through `Persistence`; the composition
root takes a direct product dependency when app code first imports it.

A package declaring no `platforms:` clause is compiled against the SDK's own
deployment floor, which is old enough to refuse `async` and `Identifiable`. That
fails only under `xcodebuild`, not under `swift build`, so run the app build after
touching a manifest. The clause does not affect the Linux job. The project uses **file-system
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

Every package except `DesignSystem` has a Swift Testing target (`@Test` / `#expect`, not
XCTest). The app target has no tests; it is a composition root with an empty scene.

```bash
swift test --package-path Packages/PowerliftingCore
swift test --package-path Packages/RepositoryInterface
swift test --package-path Packages/Persistence
swift test --package-path Packages/RepositoryFakes
swift test --package-path Packages/SeedContent
swift test --package-path Packages/SeedImport
swift test --package-path Packages/RemoteContent
swift test --package-path Packages/RemoteFetch
swift test --package-path Packages/DebugHarness
```

`PowerliftingCoreTests` is held to the same no-Apple-frameworks rule as the module
it tests, and runs on the Linux job too. In particular `Codable` is asserted
through the hand-rolled `Encoder`/`Decoder` in
`Tests/PowerliftingCoreTests/CodableProbe*.swift`, never `JSONEncoder`.

`RepositoryInterfaceTests` is under no such rule and does use `JSONEncoder`. One
thing not to assert with it: **key order**. It emits keys in per-process hash
order, so the order differs between runs; assert key spelling and the set of keys
instead, as `RecordCodingTests` does.

`PowerliftingCore` is held to ≥ 90% line coverage. The script counts only files
under the package's `Sources/`, and requires `python3`:

```bash
./scripts/coverage.sh --threshold 90
```

The suite is also held to a runtime budget of 5 seconds. The gate prints the
reading on every run, and `--self-test` proves it can fail:

```bash
./scripts/check-suite-runtime.sh
```

It covers `PowerliftingCore` only, and names it rather than globbing — a package
with a real store behind its tests is expected to be slower. The script's header
says what a failure here actually means.

Three CI assertions that also run locally — the app target's Swift build
settings, the `@unchecked Sendable` justifications, and the runtime gate's own
proof:

```bash
./scripts/audit-app-build-settings.sh
./scripts/audit-unchecked-sendable.sh
./scripts/check-suite-runtime.sh --self-test
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
  `CodingKeys`, and pin key spelling *and* key order by assertion. Where the keys
  are not all known at compile time, the constants and the write order are still
  declared; only the `CodingKeys` enum gives way to a `CodingKey` struct.
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

Nine custom rules beyond the standard set, in `.swiftlint.yml` under
`custom_rules`:

| Rule | Enforces |
|---|---|
| `no_color_literals` | `G-7.7` — colour tokens, not literals |
| `no_raw_font_sizes` | `G-7.7` — typography tokens, not point sizes |
| `no_magic_spacing` | `G-7.7` — spacing tokens, not numbers |
| `no_swiftdata_outside_persistence` | `TR-0.1.2` — only `Persistence` imports SwiftData |
| `no_foundation_in_core` | `NFR-0.2` — `PowerliftingCore` is Foundation-free |
| `no_imports_in_core` | `NFR-0.2` — `PowerliftingCore/Sources` imports nothing |
| `no_hard_delete_outside_purge` | `G-1.3` — deletion is soft outside `Persistence/Purge/` |
| `no_bare_save_in_persistence` | `G-1.2`/`G-2.4` — `saveStamped(at:)`, not `save()` |
| `no_networking_in_seed_import` | `NFR-1.7`/`G-2.1` — `SeedImport` reads the app bundle only |

One built-in rule is configured rather than left at its defaults: `missing_docs`
(`NFR-0.3`), repo-wide, with `excludes_inherited_types: false`. At the default it
skips any type carrying a conformance clause together with all of its members,
which in `PowerliftingCore` is every type.

Each rule is verified against a fixture that violates it on purpose. Run this
after touching any rule — a broken regex, a path filter that matches nothing or a
relaxed option leaves `swiftlint lint` green while enforcing nothing:

```bash
./scripts/verify-lint-rules.sh
```

Two documentation gates run in the same CI job:

```bash
./scripts/check-doc-ratio.sh    # `///` lines against code, Packages/*/Sources, max 1.5 aggregate
./scripts/check-doc-units.sh    # a public Int or Double under a dimensioned name states its unit and range
```

Both take `--help`. `check-doc-ratio.sh --per-file` reports every file when the
aggregate fails; `check-doc-units.sh --list` prints the declarations it checks.

So does one schema gate, which keeps CloudKit compatible without enabling it —
no iCloud entitlement, no source naming a `cloudKitDatabase`, no custom migration
stage, and every `@Model` present in `SchemaV1.models` — which is both the store's
schema and the list the compatibility tests audit, so an entity cannot join one
without joining the other:

```bash
./scripts/check-cloudkit.sh
./scripts/check-cloudkit.sh --self-test   # each check, in both directions
```

To lint on every build, add a **Run Script** build phase to the `Attempt` target
with `if which swiftlint > /dev/null; then swiftlint; fi`, and untick "Based on
dependency analysis".

## CI

`.github/workflows/ci.yml` runs on every push and pull request to `main`:

| Job | What it does |
|---|---|
| **Build** | audits the app target's build settings, checks the debug harness is excluded from the app (and that the check itself fires), then builds the app |
| **Package tests** | `PowerliftingCore` with coverage, then every package built and tested with warnings as errors (discovered by glob), the runtime gate and its proof, the warnings-gate proof, the `@unchecked Sendable` audit |
| **Linux core build** | builds and tests `PowerliftingCore` and `RepositoryInterface` on `ubuntu-latest` in a Swift container |
| **SwiftLint** | lint, lint-rule verification, format check, doc-ratio and doc-units gates |

All four are **required checks on `main`**, so a red run blocks the merge. The
whole workflow takes about a minute.

The `linux` job covers `PowerliftingCore` and `RepositoryInterface` —
`Persistence` and `DesignSystem` are Apple-only by design. It is not just a second
build: it is the only place `RepositoryInterface`'s independence from SwiftData is
mechanically checked, since the module does not exist there. Its container tag is
pinned to an exact patch version; bump it on its own.

Two things to know before editing the workflow. A required check is matched by
its **display name**, so renaming a job silently drops it from the protection
rule — the old name stays listed and never reports again. And a **newly added**
job is unprotected until its first run, because GitHub cannot mark a check
required until it has reported once.
