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

/// Where in the document something was found, as an author would search for it: `exercises[3].id`,
/// and the empty string at the document root.
///
/// Shared by both decode-time failures so they agree on how a position is spelled. A `CodingKey`
/// for an array index spells itself `Index 3`, which is a debugger's phrasing rather than a
/// reader's.
func seedLocation(of path: [any CodingKey]) -> String {
    path.reduce(into: "") { rendered, key in
        if let index = key.intValue {
            rendered += "[\(index)]"
        } else {
            rendered += rendered.isEmpty ? key.stringValue : ".\(key.stringValue)"
        }
    }
}

/// The one failure a decoder raises that is a *content* mistake rather than a malformed document.
///
/// A misspelled key is silently dropped by `Codable`, which for a hand-authored catalogue is the
/// worst available outcome: `"parent"` for `parentExerciseID` validates clean and produces a root
/// exercise, so `FR-1.1.7`'s parent → variations view is quietly missing a row. Raised on decode
/// because that is where the evidence is; `SeedCatalogueValidator` turns it back into a failure.
enum SeedDecodingFailure: Error {
    case unrecognisedField(name: String, location: String)
}

/// The key to report out of those an object carries but does not declare, or `nil` if it declares
/// them all.
///
/// The sorted pick is what stops the reported key from depending on the order a decoder happens to
/// enumerate an object in — Foundation promises no order for `allKeys`, and `TR-0.5.2` decodes the
/// same bytes on a server rather than on this toolchain.
///
/// It is a function of its own because that is the only place the guarantee can be *observed*: the
/// JSON decoder here hands `allKeys` over already sorted, so no payload can present the unsorted
/// input the sort exists to survive.
func unrecognisedKey(among present: [String], declared recognised: Set<String>) -> String? {
    present.filter { !recognised.contains($0) }.min()
}

extension KeyedDecodingContainer {
    /// Throws ``SeedDecodingFailure/unrecognisedField(name:location:)`` if the object carries a key
    /// this type does not declare.
    func rejectUnrecognisedFields(from decoder: any Decoder) throws {
        // `allKeys` on this container drops the keys `K` cannot spell, which is exactly the set
        // wanted: subtracting it from every key the object carries leaves the unrecognised ones.
        let recognised = Set(allKeys.map(\.stringValue))
        let present = try decoder.container(keyedBy: AnyCodingKey.self).allKeys.map(\.stringValue)
        if let unrecognised = unrecognisedKey(among: present, declared: recognised) {
            // The decoder's own path, which is the only thing here that knows *which* entry: the
            // entry's `id` has not been decoded at this point, and may itself be the broken field.
            throw SeedDecodingFailure.unrecognisedField(
                name: unrecognised, location: seedLocation(of: decoder.codingPath))
        }
    }
}
