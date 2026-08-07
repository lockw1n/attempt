/// A number of identical plates on **one** side of the bar.
public struct PlateCount: Sendable, Hashable {
    /// The mass of a single plate.
    public let plate: Weight

    /// How many go on each side.
    ///
    /// In a loading ``PlateCalculator`` produced this is at least one: an unused denomination is
    /// absent rather than present with a count of zero. That is the calculator's guarantee and not
    /// this type's — the initialiser takes any `Int`, because nothing in the module consumes a
    /// hand-built loading and a failable initialiser here would buy a boundary no caller crosses.
    public let count: Int

    /// Creates a plate count.
    public init(plate: Weight, count: Int) {
        self.plate = plate
        self.count = count
    }
}

/// A loaded bar: what it weighs, and what goes on each side (`TR-0.2.7`).
public struct PlateLoading: Sendable, Hashable {
    /// The whole bar as loaded — bar plus both collars plus twice the per-side plates.
    public let totalWeight: Weight

    /// The plates for **one** side.
    ///
    /// In a loading ``PlateCalculator`` produced these are heaviest first with each denomination
    /// appearing once, and empty for a bar carrying no plates — which is a loading like any other
    /// rather than a refusal. Ordering and uniqueness are the calculator's guarantee rather than
    /// this type's; see ``PlateCount/count`` for why neither is enforced here.
    public let perSide: [PlateCount]

    /// Creates a loading.
    public init(totalWeight: Weight, perSide: [PlateCount]) {
        self.totalWeight = totalWeight
        self.perSide = perSide
    }
}

/// What a target weight loads to, given a bar and an inventory (`TR-0.2.7`, `FR-1.4.4`).
///
/// The two cases are exclusive: an exactly loadable target is never reported as ``nearest(below:above:)``
/// with two equal arms, so a caller can switch on this rather than compare weights to find out
/// which happened.
public enum PlateLoadingResult: Sendable, Hashable {
    /// The target loads exactly.
    case exact(PlateLoading)

    /// The target does not load, with the closest loadings either side of it.
    ///
    /// - Parameters:
    ///   - below: The heaviest loading under the target, or `nil` when the target is lighter than
    ///     the bar and its collars.
    ///   - above: The lightest loading over the target, or `nil` when the inventory cannot reach it.
    ///
    /// Never both `nil`: a bar carrying no plates is always loadable, so it is either below the
    /// target or above it.
    case nearest(below: PlateLoading?, above: PlateLoading?)
}
