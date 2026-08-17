/// A dot-separated version string that can be ordered against another one.
///
/// **Trailing zeros are not significant**, so `1.2` and `1.2.0` are the same version. That is not
/// tidiness: the shipped `MARKETING_VERSION` and the published `minimumSupportedVersion` are written
/// to different widths, and a comparison that treated the shorter one as smaller would lock out the
/// build it was meant to allow.
///
/// Parsing is deliberately narrow — digits and dots, nothing else. Anything richer (`1.0.0-beta`,
/// `1.0 (42)`) fails to parse, and a version that will not parse cannot block anyone: see
/// ``UpgradeGate``.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    /// The version exactly as it was written, which is what an upgrade prompt shows.
    public let text: String

    /// The numbers, trailing zeros dropped so that two widths of the same version compare equal —
    /// which leaves an all-zero version with none at all, since a missing field already compares as
    /// zero.
    private let components: [Int]

    /// Reads a version, or `nil` when `string` is not one.
    ///
    /// Every field must be a non-empty run of ASCII digits. A field too large for `Int` is refused
    /// rather than truncated.
    public init?(_ string: String) {
        var parsed: [Int] = []
        for field in string.split(separator: ".", omittingEmptySubsequences: false) {
            // Both halves carry weight. `Int(_:)` accepts a leading sign, so without the digit
            // check `+1.0` and `-1.0` would parse as versions; `Int` is here for the field too
            // large to hold, which no character check can see, and for the non-ASCII digit that
            // `isNumber` alone admits.
            guard !field.isEmpty, field.allSatisfy({ $0.isNumber }), let value = Int(field)
            else { return nil }
            parsed.append(value)
        }
        while parsed.last == 0 { parsed.removeLast() }

        text = string
        components = parsed
    }

    /// The version as it was written.
    public var description: String { text }

    /// Compares field by field, treating a missing field as zero.
    ///
    /// Numeric per field rather than lexicographic over the string, which is the difference between
    /// `1.10` being above `1.9` and being below it.
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    /// Equal when the numbers are, whatever width they were written to — see the type's note.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components == rhs.components
    }
}
