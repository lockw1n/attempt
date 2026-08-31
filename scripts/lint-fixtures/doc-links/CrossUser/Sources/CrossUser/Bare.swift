import CrossBase

/// Holds an ``Anchor``, without naming the module.
///
/// Deliberately broken: DocC does not search sibling modules, so this is the failure that
/// Qualified.swift's module-qualified spelling is the fix for.
public struct Bare {
    /// The anchor.
    public let anchor: Anchor

    /// Creates one.
    ///
    /// - Parameter anchor: The anchor to hold.
    public init(anchor: Anchor) {
        self.anchor = anchor
    }
}
