/// A bar loaded to some weight.
public struct Barbell {
    /// The load on the bar, in grams.
    public let grams: Int

    /// Creates a loaded bar.
    ///
    /// - Parameter grams: The load, in grams.
    public init(grams: Int) {
        self.grams = grams
    }

    /// Adds a plate pair to ``grams``, which is the link this fixture proves resolves.
    ///
    /// The second parameter is undocumented on purpose: DocC warns about it, and the gate is meant
    /// to exempt that warning rather than merely fail to notice it.
    ///
    /// - Parameter plate: One plate's mass, in grams.
    public func loaded(with plate: Int, count: Int) -> Barbell {
        Barbell(grams: grams + plate * count)
    }
}
