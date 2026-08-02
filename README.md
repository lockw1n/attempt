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

Then pick a simulator and press ⌘R. From the command line:

```bash
xcodebuild -project Attempt.xcodeproj -scheme Attempt -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
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

Build every package from the command line, with warnings treated as errors:

```bash
./scripts/build-packages.sh --test
```

There is no root package, so a bare `swift build` at the repo root fails; the
script iterates the packages for you. To work on one in isolation, pass its path
(`./scripts/build-packages.sh Packages/PowerliftingCore`).

The dependency rule runs one way only: `Persistence` may import
`PowerliftingCore`, never the reverse, and the app may import all three. Two
constraints are load-bearing rather than stylistic:

- **`PowerliftingCore` imports no Apple framework** — not `Foundation`, not
  `SwiftUI`. It must compile on Linux, and the `linux` CI job builds and tests
  the package in a Swift container to prove it. Note the job catches the
  `SwiftUI`/`SwiftData` half only: Foundation ships on Linux too, so a stray
  `import Foundation` stays green there. That half is caught by the
  `no_foundation_in_core` SwiftLint rule instead — see **Custom rules** below.
- **Only `Persistence` imports `SwiftData`.** Everything else reaches storage
  through repository protocols that expose value types and DTOs.

All three packages are **linked into the app target** as local package
references, so `xcodebuild` builds them alongside the app and the layering above
is real rather than aspirational.

The Xcode project uses **file-system synchronized groups**, so the folder tree on
disk *is* the project structure for the app target, and adding or removing a file
does not churn `.pbxproj`.

`Attempt.xcodeproj` is hand-managed and tracked in git. Generating it from an
XcodeGen manifest was considered and **deferred to Phase 1**: with one committer
and synchronized groups already in place, the merge conflicts a generator prevents
cannot currently happen. The app target's four Swift build settings are guarded by
a CI assertion instead, since a setting buried in `.pbxproj` is easy to regress
unnoticed:

```bash
./scripts/audit-app-build-settings.sh
```

See `docs/phase-0/tasks/T-0.03-*` for the generator re-adoption triggers.

### Building the app

```bash
xcodebuild build -project Attempt.xcodeproj -scheme Attempt \
  -destination 'generic/platform=iOS Simulator'
```

No special flags, and ⌘B in Xcode works. This was briefly not true: while the
package manifests carried `.treatAllWarnings(as: .error)`, Xcode's
`-suppress-warnings` for package dependencies conflicted with it and the build
could only be driven from the command line with `SUPPRESS_WARNINGS=NO`. The
warnings gate moved to `scripts/` to fix that — see **Warnings are errors** below.

## Conventions

**Concurrency.** Packages build in Swift 6 language mode with
`.defaultIsolation(nil)` — declarations are `nonisolated` unless they say
otherwise, so the domain layer stays actor-agnostic. The app target is the
deliberate exception: it builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
so its types are implicitly `@MainActor` unless marked otherwise, and anything
running off the main actor must be declared `nonisolated` explicitly. Domain
types are `Sendable` value types — note that `public` types get no implicit
`Sendable` synthesis, so write the conformance.

`@unchecked Sendable` is permitted only with a written justification. Put
`Sendable justification: <why>` on the same line or in the comment block
immediately above the declaration — a blank line between the two breaks the
association and fails the audit:

```bash
./scripts/audit-unchecked-sendable.sh
```

**Warnings are errors.** The app target sets
`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`. The packages get it from command-line
flags rather than their manifests — build them through the script and a warning
fails the build:

```bash
./scripts/build-packages.sh --test
```

Packages are discovered by globbing `Packages/*/Package.swift`, so a new package
is covered the moment it exists. The flags have one definition, in
`scripts/swift-strict-flags.sh`, and `scripts/verify-warnings-gate.sh` proves
they still turn a warning into a failure.

A bare `swift build` does **not** fail on warnings. That is the accepted cost of
keeping the app buildable from Xcode: the manifests used to carry
`.treatAllWarnings(as: .error)`, but Xcode injects `-suppress-warnings` into
package dependencies and the compiler rejects both flags together, which made
⌘B impossible once the packages were linked. See `scripts/swift-strict-flags.sh`
for what was tried. CI catches a stray warning on the next push either way.

**Weights are `Int` grams.** No floating-point weight is ever persisted. Use the
`Weight` type for every weight-bearing value; kilograms and pounds are display
concerns only. `Weight` is the enforcement, not just the convention — the only
initialisers that accept a `Double` are `init?(kilograms:rounding:)` and
`init?(pounds:rounding:)`, both of which make you name a `RoundingStrategy`, and
both of which return `nil` rather than trapping on NaN or overflow. It is signed,
because it doubles as a delta (an increment, a deload, a target-versus-loaded
gap). Display goes through `formatted(in:precision:)`, which renders digits only
— appending "kg" is the UI layer's job, since localisation is Foundation.

**Derived values are recomputed, never stored as truth.** Estimated 1RMs,
personal records and training maxes are calculated from logged sets. Cached
copies carry a `computationVersion` that invalidates them.

**Deletion is soft.** Entities carry `deletedAt`; hard deletion happens only
through an explicit purge routine.

**Strings.** User-facing text goes through `String(localized:)` and lands in
`Resources/Localizable.xcstrings`.

**Commits carry requirement IDs.** Lead the subject with the requirement the work
traces to, then a colon:

```
TR-0.2.1: add Weight value type
G-6.4, TR-0.1.3: enable strict concurrency across the packages
```

Requirement IDs are `G-*`, `FR-*`, `NFR-*`, `TR-*`, `OUT-*`, `DOD-*` and `D-*`.
Comma-separate when a commit covers more than one. This is what keeps
`git log --grep TR-0.2` meaningful, and **it cannot be backfilled** — once a
commit is pushed, rewriting the subject means rewriting shared history, which
costs more than the missing search hit. Work that traces to no requirement is
scope creep; resolve that before committing rather than inventing an ID.

An optional hook warns when a subject has no ID. It never blocks a commit — a
rejected commit at the wrong moment costs more than a missed grep:

```bash
git config core.hooksPath scripts/git-hooks
```

Pull requests use `.github/pull_request_template.md`, which asks for the same IDs
plus the task ID from `docs/phase-0/tasks.md`.

## Testing

`PowerliftingCore` and `Persistence` each have a Swift Testing target (`@Test` /
`#expect`, not XCTest). The packages are linked into `Attempt.xcodeproj`, but
there is still no root package and no umbrella scheme, so run them via the
script or one at a time:

```bash
swift test --package-path Packages/PowerliftingCore
```

```bash
swift test --package-path Packages/Persistence
```

The app target has no tests: it is a composition root with an empty scene.

`PowerliftingCoreTests` is held to the same no-Apple-frameworks rule as the
module it tests — a suite that drifts from its module's constraints stops being
evidence about that module, and it runs on the Linux job too. In particular,
`Codable` is asserted through the hand-rolled `Encoder`/`Decoder` in
`Tests/PowerliftingCoreTests/CodableProbe.swift`, **not** `JSONEncoder`. Note
that CI will not catch you here: the Linux job rejects `import SwiftUI`, but
Foundation ships on Linux, so a `JSONEncoder` round-trip compiles and goes green
everywhere while quietly breaking the rule.

### Coverage

`PowerliftingCore` is held to ≥ 90% line coverage. `scripts/coverage.sh` runs
the suite with coverage collection and reports the figure:

```bash
./scripts/coverage.sh --threshold 90
```

It exits non-zero below the threshold, which defaults to `0` until the gate is
switched on. It counts only files under the package's `Sources/` — the raw
llvm-cov totals include the test target and Swift Testing's generated runner,
which reported 85% coverage back when the module contained no code at all.
Requires `python3`.

## Linting and formatting

[SwiftLint](https://github.com/realm/SwiftLint) is configured in `.swiftlint.yml`
and runs in CI over **both `Attempt/` and `Packages/`**:

```bash
brew install swiftlint
swiftlint lint --strict
```

Formatting is `swift format`, which ships with the toolchain — nothing to
install. Config lives in `.swift-format`: 4-space indentation and a 120-column
limit, matching `.editorconfig` and SwiftLint's `line_length` rather than the
tool's own defaults of 2 and 100.

```bash
swift format lint --strict --recursive Attempt Packages
```

```bash
swift format --in-place --recursive Attempt Packages
```

**`--strict` is not optional.** Without it, `swift format lint` prints violations
as warnings and still **exits 0**, so a CI step that omits it is decorative.

### Custom rules

Five rules beyond the standard set, in `.swiftlint.yml` under `custom_rules`:

| Rule | Enforces |
|---|---|
| `no_color_literals` | `G-7.7` — colour tokens, not literals |
| `no_raw_font_sizes` | `G-7.7` — typography tokens, not point sizes |
| `no_magic_spacing` | `G-7.7` — spacing tokens, not numbers |
| `no_swiftdata_outside_persistence` | `TR-0.1.2` — only `Persistence` imports SwiftData |
| `no_foundation_in_core` | `NFR-0.2` — `PowerliftingCore` is Foundation-free |

The last one carries real weight: the Linux CI job **cannot** catch
`import Foundation`, because Foundation compiles on Linux. This rule is the only
mechanical enforcement of that half of `NFR-0.2`.

Rules are verified against fixtures that violate them on purpose:

```bash
./scripts/verify-lint-rules.sh
```

A rule whose regex is broken, or whose path filter matches nothing, leaves
`swiftlint lint` green while enforcing nothing — a failure that is invisible
because it looks like success. The script also guards the opposite direction:
`PowerliftingCore.swift` and `Persistence.swift` both *mention* their banned
import in prose, and must not trigger. That works because the two import rules
set `match_kinds`, which excludes `comment` syntax.

To lint on every build, add a **Run Script** build phase to the `Attempt` target
with `if which swiftlint > /dev/null; then swiftlint; fi` and untick "Based on
dependency analysis".

## CI

`.github/workflows/ci.yml` builds the app, runs both package test suites with
coverage, builds `DesignSystem` (it has no test target, so nothing else compiles
it), audits `@unchecked Sendable`, builds and tests `PowerliftingCore` on Linux,
and runs SwiftLint on every push and pull request to `main`.

The **`linux`** job ("Linux core build") runs on `ubuntu-latest` inside
`container: swift:6.3.3-noble` and covers `PowerliftingCore` only — `Persistence`
and `DesignSystem` are Apple-only by design and are not expected to compile
there. It is the enforcement behind the no-Apple-framework rule above; nothing
else in the workflow would notice an `import SwiftUI` in the domain layer,
because that compiles fine on macOS. It does **not** catch `import Foundation`,
which compiles on Linux as well — see the rule above. The image tag is pinned to
an exact patch version on purpose — see the comment above the job.

All three macOS jobs run on **`macos-26`** (Xcode 26), and every job checks out
with `actions/checkout@v7`. Both were bumped on 2026-08-02: `macos-15` ships
Xcode 16.x, which cannot parse the tools-version 6.2 manifests at all and only
*warned* about the iOS 26.5 deployment target before clamping it.

**All four jobs are required checks on `main`**, so a red run blocks the merge —
verified with a deliberately failing test, not assumed. The whole workflow runs
in about a minute.

Two things to know if you edit the workflow. A required check is matched by its
**display name**, so renaming a job silently drops it from the protection rule:
the old name stays listed as required and never reports again, leaving `main`
either permanently blocked or quietly unprotected. And a **newly added** job is
unprotected until its first run, because GitHub cannot offer a check as required
until it has reported once — add the job, let it run, then re-open the rule.

One further thing worth knowing: warnings are errors, and runner image labels
move — a toolchain bump can redden CI with no commit behind it, which is the gate
working rather than a flake, and is why the `linux` container tag is pinned
rather than floating.

The `linux` job's tripwire has been tested rather than assumed: an `import
CoreGraphics` in the domain layer failed its build step while all three macOS
jobs stayed green (2026-08-02, reverted).
