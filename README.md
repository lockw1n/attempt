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

The project uses Xcode's **file-system synchronized groups**, so the folder tree
on disk *is* the project structure — create a folder in Finder or your editor and
it appears in Xcode automatically. There is no need to add files to the
`.pbxproj` by hand.

```
Attempt/
├── App/                     App entry point, root scene, app-wide wiring
├── Features/                One folder per feature; views + view models together
│   └── Home/
├── Models/                  Domain types shared across features
├── Core/                    Reusable infrastructure, no feature knowledge
│   ├── Networking/          APIClient, Endpoint
│   ├── DesignSystem/        Theme tokens (spacing, radii, animation)
│   └── Extensions/          Extensions on system types
├── Resources/               String catalogs, fonts, data files
└── Assets.xcassets          Colors, images, app icon
```

The rule of thumb: `Features/` may import from `Core/` and `Models/`, but never
the other way round. If something in `Core/` needs to know about a feature, it
belongs in that feature instead.

## Conventions

**Concurrency.** The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
so every type is implicitly `@MainActor` unless marked otherwise. Anything that
should run off the main actor — networking, parsing, disk I/O — must be declared
`nonisolated` explicitly. `Core/Networking` is the worked example.

**State.** Model loadable content with `ViewState<Value>` (`Models/ViewState.swift`)
rather than separate `isLoading` / `value` / `error` properties, so a view can
never be loading and failed at the same time.

**Errors.** Lower layers map their failures into `AppError` (`Models/AppError.swift`).
Views should never see a `URLError` or a `DecodingError`.

**View models.** `@MainActor @Observable final class`, dependencies injected
through the initialiser so tests can substitute stubs. See `Features/Home/HomeViewModel.swift`.

**Design tokens.** Use `Theme.Spacing`, `Theme.Radius`, and `Theme.Animation`
instead of hard-coded numbers.

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
