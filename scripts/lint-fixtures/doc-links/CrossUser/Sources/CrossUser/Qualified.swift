import CrossBase

/// Holds a ``CrossBase/Anchor``, naming the module in the path.
///
/// This link resolves, and only because CrossBase's graph is in the same run.
public struct Qualified {
    /// The anchor.
    public let anchor: Anchor

    /// Creates one.
    ///
    /// - Parameter anchor: The anchor to hold.
    public init(anchor: Anchor) {
        self.anchor = anchor
    }
}
