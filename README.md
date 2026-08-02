# Attempt

A SwiftUI app for iOS.

## Requirements

| | |
|---|---|
| Xcode | 26.6 (build 17F113) |
| Swift | 6.3 toolchain, Swift 5 language mode |
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

Build the packages from the command line:

```bash
cd Packages/PowerliftingCore && swift build
```

The dependency rule runs one way only: `Persistence` may import
`PowerliftingCore`, never the reverse, and the app may import all three. Two
constraints are load-bearing rather than stylistic:

- **`PowerliftingCore` imports no Apple framework** — not `Foundation`, not
  `SwiftUI`. It must compile on Linux, and CI proves it.
- **Only `Persistence` imports `SwiftData`.** Everything else reaches storage
  through repository protocols that expose value types and DTOs.

The Xcode project still uses **file-system synchronized groups**, so the folder
tree on disk *is* the project structure for the app target. That project is
hand-managed for now and will be generated from an XcodeGen manifest, at which
point the packages get linked into it.

## Conventions

**Concurrency.** Packages build in Swift 6 language mode. The app target builds
with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so its types are implicitly
`@MainActor` unless marked otherwise; anything running off the main actor must
be declared `nonisolated` explicitly. Domain types are `Sendable` value types.

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

## Testing

There is no test target yet. Adding one needs Xcode's UI, because a new target
means new build settings and phases in the `.pbxproj`:

1. **File → New → Target… → Unit Testing Bundle**, name it `AttemptTests`.
2. Repeat with **UI Testing Bundle** for `AttemptUITests` if you want UI tests.
3. Uncomment the test step in `.github/workflows/ci.yml`.

New targets in Xcode 26 default to Swift Testing (`@Test` / `#expect`) rather
than XCTest. Once the target exists:

```bash
xcodebuild test -project Attempt.xcodeproj -scheme Attempt -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

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

`.github/workflows/ci.yml` builds the app and runs SwiftLint on every push and
pull request to `main`. The test job is commented out until a test target exists.
