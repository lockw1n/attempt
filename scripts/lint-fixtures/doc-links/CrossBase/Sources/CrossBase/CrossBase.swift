/// The symbol CrossUser links at, from a module that is not CrossUser's own.
public struct Anchor {
    /// The load, in grams.
    public let grams: Int

    /// Creates an anchor.
    ///
    /// - Parameter grams: The load, in grams.
    public init(grams: Int) {
        self.grams = grams
    }
}
