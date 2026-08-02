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

Build the packages from the command line — one at a time, since there is no root
package until the Xcode project is generated:

```bash
swift build --package-path Packages/PowerliftingCore
```

The dependency rule runs one way only: `Persistence` may import
`PowerliftingCore`, never the reverse, and the app may import all three. Two
constraints are load-bearing rather than stylistic:

- **`PowerliftingCore` imports no Apple framework** — not `Foundation`, not
  `SwiftUI`. It must compile on Linux, and the `linux` CI job builds and tests
  the package in a Swift container to prove it. Note the job catches the
  `SwiftUI`/`SwiftData` half only: Foundation ships on Linux too, so a stray
  `import Foundation` stays green there and is caught by review alone for now.
- **Only `Persistence` imports `SwiftData`.** Everything else reaches storage
  through repository protocols that expose value types and DTOs.

The Xcode project still uses **file-system synchronized groups**, so the folder
tree on disk *is* the project structure for the app target. That project is
hand-managed for now and will be generated from an XcodeGen manifest, at which
point the packages get linked into it.

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

**Warnings are errors.** Every target sets `.treatAllWarnings(as: .error)`, and
the app target sets `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, so a warning fails
the build locally and not just in CI. To iterate past one mid-refactor:

```bash
swift build --package-path Packages/PowerliftingCore -Xswiftc -no-warnings-as-errors
```

**Weights are `Int` grams.** No floating-point weight is ever persisted. Use the
`Weight` type for every weight-bearing value; kilograms and pounds are display
concerns only.

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
`#expect`, not XCTest). The packages are not linked into `Attempt.xcodeproj`
yet, so there is no root package and no umbrella scheme — run each in place:

```bash
swift test --package-path Packages/PowerliftingCore
```

```bash
swift test --package-path Packages/Persistence
```

The app target has no tests: it is a composition root with an empty scene.

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

## Linting

[SwiftLint](https://github.com/realm/SwiftLint) is configured in `.swiftlint.yml`
but not installed or wired into the build:

```bash
brew install swiftlint
swiftlint lint
```

To run it on every build, add a **Run Script** build phase to the `Attempt`
target with `if which swiftlint > /dev/null; then swiftlint; fi` and untick
"Based on dependency analysis".

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

**All four jobs are green** as of 2026-08-02. Four caveats, because green here
means less than it looks:

- **`build` passes on `macos-15` only because it never touches the packages.**
  That runner ships Xcode 16.x, which cannot parse the tools-version 6.2
  manifests — but `xcodebuild` runs against `Attempt.xcodeproj`, and the packages
  are not linked into it yet. It will go red the moment T-0.03 links them, so the
  runner image bump is a prerequisite for that task, not just cleanup.
- **`build` warns rather than fails on the deployment target.** `IPHONEOS_DEPLOYMENT_TARGET`
  is 26.5 and Xcode 16.4 supports up to 18.5, which is a warning; Xcode clamps and
  carries on. Warnings-as-errors does not escalate it — that setting covers Swift
  compiler diagnostics, and this is a build-settings one.
- **`lint` passes trivially.** `.swiftlint.yml` has `included: [Attempt]`, so
  nothing under `Packages/` is linted at all. A green SwiftLint run says nothing
  about the packages until T-0.05 widens the scope.
- No job is a required check in branch protection yet, so a red run would not
  block a merge anyway.

One further thing worth knowing: warnings are errors, and runner image labels
move — a toolchain bump can redden CI with no commit behind it, which is the gate
working rather than a flake, and is why the `linux` container tag is pinned
rather than floating.

The `linux` job's tripwire has been tested rather than assumed: an `import
CoreGraphics` in the domain layer failed its build step while all three macOS
jobs stayed green (2026-08-02, reverted).
