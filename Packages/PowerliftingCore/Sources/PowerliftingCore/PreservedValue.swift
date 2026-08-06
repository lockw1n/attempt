/// One encoded value held verbatim because this version has no type to decode it into.
///
/// It exists so a payload from a newer app version survives a round trip instead of being thrown
/// away (`NFR-2.3`). ``Prescription/unrecognised(_:)`` is its only user: `OpenVocabulary` preserves
/// an unrecognised *term*, and a prescription case from a newer version carries numbers beside its
/// discriminator that a term cannot hold.
///
/// **Two things are canonicalised rather than preserved, and both are unavoidable.** An object's
/// key *order* is not carried — a decoder's `allKeys` order is unspecified — so ``object(_:)`` is
/// re-encoded sorted by key, which is what makes encode → decode → encode stable. And a number's
/// *spelling* is not carried: `5.0` may come back as `5`. The value is preserved in both cases;
/// only the bytes of a foreign payload's first encoding may differ from its source.
///
/// Not `indirect`: the recursion runs through `Array` and `Dictionary`, which are already
/// heap-allocated.
public enum PreservedValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([PreservedValue])
    case object([String: PreservedValue])
}

// MARK: - Codable

extension PreservedValue {
    /// Decodes whatever is there, in the order that keeps a value in the narrowest case it fits:
    /// null, bool, int, double, string, array, object.
    ///
    /// `int` is tried before `double` so a whole number re-encodes as a whole number. Nothing here
    /// throws on unexpected input — being the case that accepts anything is the type's whole job —
    /// except a value outside this vocabulary entirely, which no encoder in this module produces.
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if single.decodeNil() {
                self = .null
                return
            }
            if let value = try? single.decode(Bool.self) {
                self = .bool(value)
                return
            }
            if let value = try? single.decode(Int.self) {
                self = .int(value)
                return
            }
            if let value = try? single.decode(Double.self) {
                self = .double(value)
                return
            }
            if let value = try? single.decode(String.self) {
                self = .string(value)
                return
            }
        }
        if var container = try? decoder.unkeyedContainer() {
            var elements: [PreservedValue] = []
            while !container.isAtEnd {
                elements.append(try container.decode(PreservedValue.self))
            }
            self = .array(elements)
            return
        }
        // The object branch is last and is not attempted with `try?`: anything that is none of the
        // shapes above should fail with the decoder's own diagnosis rather than with a summary of
        // it, and there is no further case to fall through to.
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var fields: [String: PreservedValue] = [:]
        for key in container.allKeys {
            fields[key.stringValue] = try container.decode(PreservedValue.self, forKey: key)
        }
        self = .object(fields)
    }

    /// Writes the value back in its own shape. Object keys are written sorted; see the type's note.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let elements):
            var container = encoder.unkeyedContainer()
            for element in elements {
                try container.encode(element)
            }
        case .object(let fields):
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                try container.encode(value, forKey: AnyCodingKey(key))
            }
        }
    }
}

/// A coding key for a wire format whose keys are not all known at compile time.
///
/// Needed because a prescription object holds a fixed envelope beside a payload whose keys may come
/// from a newer version. The declared-`CodingKeys` convention the rest of this module follows still
/// applies to every key this module *chooses*: those are named constants, written in a pinned
/// order, both asserted by test. The keys it does not choose are the ones it is preserving, and
/// they are written verbatim in sorted order.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        nil
    }
}
