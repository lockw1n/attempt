/// A type whose doc comment links to ``NoSuchSymbol``, which does not exist.
///
/// This is the whole fixture: an invalid symbol link compiles clean and lints clean, so the gate
/// is the only thing that can object to it.
public struct Dumbbell {
    /// The load on the implement, in grams.
    public let grams: Int

    /// Creates a loaded implement.
    ///
    /// - Parameter grams: The load, in grams.
    public init(grams: Int) {
        self.grams = grams
    }
}
