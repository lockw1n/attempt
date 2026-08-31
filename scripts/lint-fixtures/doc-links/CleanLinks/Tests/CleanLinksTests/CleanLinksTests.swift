import CleanLinks

/// A doc comment in a *test* target, linking to ``AlsoNoSuchSymbol``.
///
/// Deliberately broken: the gate scopes itself to modules with a directory under `Sources/`, and
/// this asserts that the scoping is real rather than accidental.
struct FixtureHelper {
    /// Builds a bar.
    static func bar() -> Barbell { Barbell(grams: 20_000) }
}
