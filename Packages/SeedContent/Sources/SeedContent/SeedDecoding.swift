import Foundation

/// A coding key that accepts any name, so a decoder can see the keys a payload actually carries.
///
/// `KeyedDecodingContainer.allKeys` reports only the keys that map onto the container's own key
/// type, so a typo is invisible through `CodingKeys` alone.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

/// The one failure a decoder raises that is a *content* mistake rather than a malformed document.
///
/// A misspelled key is silently dropped by `Codable`, which for a hand-authored catalogue is the
/// worst available outcome: `"parent"` for `parentExerciseID` validates clean and produces a root
/// exercise, so `FR-1.1.7`'s parent → variations view is quietly missing a row. Raised on decode
/// because that is where the evidence is; `SeedCatalogueValidator` turns it back into a failure.
enum SeedDecodingFailure: Error {
    case unrecognisedField(String)
}

extension KeyedDecodingContainer {
    /// Throws ``SeedDecodingFailure/unrecognisedField(_:)`` if the object carries a key this type
    /// does not declare.
    ///
    /// Reports the first such key in sorted order, so the failure does not depend on the order a
    /// decoder happens to enumerate an object in.
    func rejectUnrecognisedFields(from decoder: any Decoder) throws {
        // `allKeys` on this container drops the keys `K` cannot spell, which is exactly the set
        // wanted: subtracting it from every key the object carries leaves the unrecognised ones.
        let recognised = Set(allKeys.map(\.stringValue))
        let present = try decoder.container(keyedBy: AnyCodingKey.self).allKeys.map(\.stringValue)
        if let unrecognised = present.filter({ !recognised.contains($0) }).min() {
            throw SeedDecodingFailure.unrecognisedField(unrecognised)
        }
    }
}
