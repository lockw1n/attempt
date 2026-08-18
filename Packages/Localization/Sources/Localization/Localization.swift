/// The localisation layer (`G-3.4`): how a module's copy is stored and keyed, and how a number,
/// a date or a weight is rendered for a locale.
///
/// ## Where a module's copy lives
///
/// Every module that shows text owns a catalogue at
/// `Sources/<Target>/Resources/en.lproj/Localizable.strings`, declared with
/// `defaultLocalization: "en"` and `resources: [.process("Resources")]` in its manifest. Its keys
/// are reached through one `enum` of `LocalizedStringResource` constants per module — never through
/// a literal at the call site, which `no_literal_ui_strings` enforces.
///
/// **`.strings`, not `.xcstrings`, and the reason is that the two build systems disagree.**
/// `swift build` copies a String Catalogue into the resource bundle without compiling it, so every
/// key resolves to itself under `swift test`; `xcodebuild` compiles it to
/// `en.lproj/Localizable.strings`. A catalogue would therefore make every package-level assertion
/// about copy — a resolution test, a snapshot of a screen — pass while showing key names. The
/// `.strings` form resolves identically under both. Migrating to a catalogue is one Xcode command
/// the day SwiftPM compiles them.
///
/// A resource in a package resolves against **that package's** bundle, so a module's copy is
/// `Bundle.module`'s, not the app's. That is why each module declares its own accessors: `Bundle`
/// `.module` is per-target and cannot be handed across one.
///
/// ## The key convention
///
/// `<module>.<screen>.<element>[.<role>]`, lowercase, dot-separated, no camel case:
/// `settings.landing.units.title`, `settings.landing.error.retry`. The module segment is the
/// target's name lowercased, so a key names its own catalogue and two modules cannot collide. The
/// screen segment is the screen, not the type — `landing`, not `SettingsLandingView` — so renaming
/// a view is not a re-key. Keys are never reused for different copy: a changed meaning is a new
/// key, because a translation memory keys off the identifier and not the English.
///
/// ## Rendering
///
/// Numbers, weights, dates and percentages go through ``AppFormat``, whose styles all take an
/// explicit `Locale` — in a view, `@Environment(\.locale)`. String interpolation of a number is a
/// defect: it renders `102.5` in a locale that writes `102,5`.
public enum Localization {}
