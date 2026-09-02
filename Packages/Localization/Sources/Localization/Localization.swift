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
/// **A module with no screens names the surface instead.** `DesignSystem` owns the copy its five
/// state placeholders share, and those are shown on every screen and belong to none, so their
/// middle segment is the state — `designsystem.offline.headline` — and, where two states share one
/// string, the surface: `designsystem.state.retry`. The rule the segment is obeying is the same one
/// it obeys everywhere, which is that it must not name the type: `offline`, never
/// `OfflineStateView`.
///
/// ## The second language, and why it is all or nothing
///
/// Every catalogue ships `en.lproj` and `uk.lproj` (`FR-1.14.1`), and the pair has to stay
/// complete key for key. Once `uk` is one of a bundle's localizations, a key with no Ukrainian
/// value renders **its own identifier** on screen — the platform does not fall back to the
/// development language — so a half-translated table is worse than an untranslated app.
///
/// `scripts/check-translations.sh` holds that, over every catalogue in the repo plus the app
/// target's own String Catalogue and its `knownRegions`; it is wired into CI's lint job and
/// self-tests. Adding a key therefore means adding it twice, in the same commit. A Ukrainian
/// plural needs four categories where English needs two — `one`, `few`, `many` and `other` — and
/// the same script refuses a variable missing any of them.
///
/// The Ukrainian copy itself carries no argument for itself: the comment explaining why a string
/// is worded as it is stays in `en.lproj`, which is that fact's one home.
///
/// ## Copy, and what is not copy
///
/// A literal at a copy call site is copy and belongs in the catalogue. A literal bound to a named
/// constant is *data* — a preview's sample exercise, a stored identifier — and reaches the screen
/// through `Text(verbatim:)`. That is the one shape `no_literal_ui_strings` cannot see, so it is
/// stated here rather than enforced: a preview writing `Text(verbatim: "Squat")` inline is caught,
/// and hoisting the literal to a `Sample` constant is the intended fix, not an evasion of the rule.
///
/// ## Rendering
///
/// Numbers, weights, dates and percentages go through ``AppFormat``, whose styles all take an
/// explicit `Locale` — in a view, `@Environment(\.locale)`. String interpolation of a number is a
/// defect: it renders `102.5` in a locale that writes `102,5`.
public enum Localization {}
