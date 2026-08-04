// A minimal `Encoder`/`Decoder` pair for asserting `Codable` conformances without Foundation.
//
// Why this file exists (T-0.10). `Encodable` and `Decodable` are standard library, so conforming
// costs nothing — but `JSONEncoder` and `JSONDecoder` are Foundation, and `NFR-0.2` forbids
// Foundation in `PowerliftingCore`. The test target is held to the same rule: it runs on the
// Linux job (T-0.08) and a suite that drifts from its module's constraints stops being evidence
// about that module.
//
// The trap this avoids is that CI would not have caught it. T-0.08 proved the Linux job rejects
// `import SwiftUI` and `import CoreGraphics`, but Foundation ships on Linux via
// swift-corelibs-foundation, so a `JSONEncoder` round-trip would compile and go green on every
// job while quietly breaking the rule. Until T-0.05 adds a lint rule, this is enforced by
// choosing not to import it.
//
// What it covers. Single values — `Weight` is a bare integer of grams, `RoundingStrategy` a bare
// string, `DisplayPrecision` a bare integer — and, since T-0.13, keyed objects: `RoundingRule` is
// the module's first composite shape. The unkeyed (array) path is still a deliberate trap, because
// no type needs it yet; T-0.12's `SetRecord` carries a modifier collection and is expected to fill
// it in, the way this task filled in the keyed one. A type that reaches for a path the probe omits
// has changed its wire format, and that failure should be loud rather than silently accommodated.
//
// Key order is significant here. `ProbeValue.object` holds an *ordered* list of fields and
// compares in order, so an assertion against it pins key order as well as key spelling — which is
// what byte stability of a keyed shape means, and what T-0.20 has to assert per prescription case.

/// One encoded value — the entire vocabulary this module's wire formats use.
///
/// `object` keeps its fields in encoding order rather than in a dictionary, so equality is
/// order-sensitive. That is the point: reordering keys changes the bytes.
enum ProbeValue: Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case string(String)
    case double(Double)
    case int(Int)
    case object([ProbeField])

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): "bool(\(value))"
        case .string(let value): "string(\"\(value)\")"
        case .double(let value): "double(\(value))"
        case .int(let value): "int(\(value))"
        case .object(let fields): "object(\(fields.map(\.description).joined(separator: ", ")))"
        }
    }
}

/// One key–value pair of an encoded object, in the position it was written.
struct ProbeField: Equatable, CustomStringConvertible {
    let key: String
    let value: ProbeValue

    var description: String { "\(key): \(value)" }
}

/// Raised when a probed type uses part of the `Codable` surface this probe deliberately omits.
struct ProbeUnsupported: Error, CustomStringConvertible {
    let what: String
    var description: String { "CodableProbe does not support \(what)" }
}

// MARK: - Encoding

/// Encodes `value` and returns the `ProbeValue` it wrote — a primitive, or an object.
///
/// - Throws: `ProbeUnsupported` if `value` encodes nothing at all, or writes a primitive outside
///   `ProbeValue`'s vocabulary. Writing an *unkeyed* container is a `preconditionFailure` rather
///   than a throw, because there is no container to return in its place.
func probeEncode(_ value: some Encodable) throws -> ProbeValue {
    let storage = ProbeStorage()
    try value.encode(to: ProbeEncoder(storage: storage))
    guard let encoded = storage.value else {
        throw ProbeUnsupported(what: "a type that encoded nothing")
    }
    return encoded
}

/// Shared write target. A reference type because `Encoder` hands out containers by value.
final class ProbeStorage {
    var value: ProbeValue?
    private var object: ProbeObjectStorage?

    /// The object accumulator for this slot, created once and then reused.
    ///
    /// Reused rather than recreated because `Encoder.container(keyedBy:)` may legitimately be
    /// called more than once while encoding one value — a hand-written `encode(to:)` that grabs
    /// the container again after a branch is ordinary `Codable`, and Foundation's encoders share
    /// one backing store across those calls. Handing back a fresh accumulator each time silently
    /// discarded everything written through the earlier one: measured 2026-08-04, a type writing
    /// `a` through one container and `b` through a second encoded as `object(b: int(2))`, losing
    /// `a` with no error. Silent truncation is the one failure mode this file's header promises
    /// not to have.
    func objectStorage() -> ProbeObjectStorage {
        if let object { return object }
        let created = ProbeObjectStorage(parent: self)
        object = created
        return created
    }
}

struct ProbeEncoder: Encoder {
    let storage: ProbeStorage
    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(ProbeKeyedEncodingContainer<Key>(object: storage.objectStorage()))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        preconditionFailure("CodableProbe does not support unkeyed encoding")
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        ProbeSingleValueEncodingContainer(storage: storage)
    }
}

struct ProbeSingleValueEncodingContainer: SingleValueEncodingContainer {
    let storage: ProbeStorage
    var codingPath: [any CodingKey] { [] }

    func encodeNil() throws { storage.value = .null }
    func encode(_ value: Bool) throws { storage.value = .bool(value) }
    func encode(_ value: String) throws { storage.value = .string(value) }
    func encode(_ value: Double) throws { storage.value = .double(value) }
    func encode(_ value: Float) throws { storage.value = .double(Double(value)) }
    func encode(_ value: Int) throws { try encodeInteger(value) }
    func encode(_ value: Int8) throws { try encodeInteger(value) }
    func encode(_ value: Int16) throws { try encodeInteger(value) }
    func encode(_ value: Int32) throws { try encodeInteger(value) }
    func encode(_ value: Int64) throws { try encodeInteger(value) }
    func encode(_ value: UInt) throws { try encodeInteger(value) }
    func encode(_ value: UInt8) throws { try encodeInteger(value) }
    func encode(_ value: UInt16) throws { try encodeInteger(value) }
    func encode(_ value: UInt32) throws { try encodeInteger(value) }
    func encode(_ value: UInt64) throws { try encodeInteger(value) }

    func encode<T: Encodable>(_ value: T) throws {
        try value.encode(to: ProbeEncoder(storage: storage))
    }

    /// `ProbeValue` carries integers as `Int`, so the unsigned and 64-bit overloads have to be
    /// narrowed. `Int(exactly:)` rather than `Int(_:)` on purpose: the trapping form crashes the
    /// whole test *run* on a `UInt` above `Int.max` instead of failing one test, and this file is
    /// shared infrastructure that T-0.12 and T-0.20 are expected to extend.
    private func encodeInteger(_ value: some BinaryInteger) throws {
        guard let narrowed = Int(exactly: value) else {
            throw ProbeUnsupported(what: "the integer \(value), which does not fit in Int")
        }
        storage.value = .int(narrowed)
    }
}

/// Accumulates an object's fields and writes the growing value through to its parent.
///
/// A reference type because `Encoder` hands out containers by value, and the write-through on
/// every append means the parent holds a complete `.object` even if the encoding stops early.
final class ProbeObjectStorage {
    private let parent: ProbeStorage
    private var fields: [ProbeField] = []

    init(parent: ProbeStorage) {
        self.parent = parent
        parent.value = .object([])
    }

    func append(_ field: ProbeField) {
        fields.append(field)
        parent.value = .object(fields)
    }
}

struct ProbeKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let object: ProbeObjectStorage
    var codingPath: [any CodingKey] { [] }

    mutating func encodeNil(forKey key: Key) throws { try write(key) { try $0.encodeNil() } }
    mutating func encode(_ value: Bool, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: String, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: Double, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: Float, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: Int, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: Int8, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: Int16, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: Int32, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: Int64, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: UInt, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try write(key) { try $0.encode(value) } }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { try write(key) { try $0.encode(value) } }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        try write(key) { try $0.encode(value) }
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        // Unreachable through `encode(_:forKey:)`, which nests by re-entering `ProbeEncoder`; a
        // type that asks for a nested container directly is doing something this probe has never
        // had to model, and should say so loudly rather than encode a silently empty object.
        preconditionFailure("CodableProbe does not support explicitly nested keyed encoding")
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        preconditionFailure("CodableProbe does not support unkeyed encoding")
    }

    func superEncoder() -> any Encoder {
        preconditionFailure("CodableProbe does not support class inheritance")
    }

    func superEncoder(forKey key: Key) -> any Encoder {
        preconditionFailure("CodableProbe does not support class inheritance")
    }

    /// Encodes one field through a fresh single-value container and appends the result.
    ///
    /// Routing every key back through `ProbeSingleValueEncodingContainer` is what makes a nested
    /// `Weight` come out as a bare `int` rather than a wrapper object: the nested type simply gets
    /// its own encoder, and whichever container *it* asks for decides its shape.
    private func write(_ key: Key, _ body: (ProbeSingleValueEncodingContainer) throws -> Void) throws {
        let storage = ProbeStorage()
        try body(ProbeSingleValueEncodingContainer(storage: storage))
        guard let encoded = storage.value else {
            throw ProbeUnsupported(what: "the key \"\(key.stringValue)\", which encoded nothing")
        }
        object.append(ProbeField(key: key.stringValue, value: encoded))
    }
}

// MARK: - Decoding

/// Decodes a `type` from a single encoded primitive.
///
/// - Throws: `ProbeUnsupported` for containers this probe omits, or `DecodingError` when the type
///   rejects the value — which is the point of several of the tests.
func probeDecode<T: Decodable>(_ type: T.Type, from value: ProbeValue) throws -> T {
    try T(from: ProbeDecoder(value: value))
}

struct ProbeDecoder: Decoder {
    let value: ProbeValue
    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let fields) = value else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected an object but the probe holds \(value)"
                )
            )
        }
        return KeyedDecodingContainer(ProbeKeyedDecodingContainer<Key>(fields: fields))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw ProbeUnsupported(what: "unkeyed decoding")
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        ProbeSingleValueDecodingContainer(value: value)
    }
}

struct ProbeKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let fields: [ProbeField]
    var codingPath: [any CodingKey] { [] }
    var allKeys: [Key] { fields.compactMap { Key(stringValue: $0.key) } }

    func contains(_ key: Key) -> Bool {
        fields.contains { $0.key == key.stringValue }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try single(key).decodeNil()
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try single(key).decode(type) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try single(key).decode(type) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try single(key).decode(type) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try single(key).decode(type) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try single(key).decode(type) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try single(key).decode(type) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try single(key).decode(type) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try single(key).decode(type) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try single(key).decode(type) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try single(key).decode(type) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try single(key).decode(type) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try single(key).decode(type) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try single(key).decode(type) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try single(key).decode(type) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try T(from: ProbeDecoder(value: try field(key)))
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try ProbeDecoder(value: try field(key)).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw ProbeUnsupported(what: "unkeyed decoding")
    }

    func superDecoder() throws -> any Decoder {
        throw ProbeUnsupported(what: "class inheritance")
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        throw ProbeUnsupported(what: "class inheritance")
    }

    /// The value stored under `key`, or `keyNotFound` — which is the error a hand-written decoder
    /// is expected to surface for a missing field, so tests can assert on it.
    private func field(_ key: Key) throws -> ProbeValue {
        guard let match = fields.first(where: { $0.key == key.stringValue }) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "No value associated with key \"\(key.stringValue)\""
                )
            )
        }
        return match.value
    }

    private func single(_ key: Key) throws -> ProbeSingleValueDecodingContainer {
        ProbeSingleValueDecodingContainer(value: try field(key))
    }
}

struct ProbeSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: ProbeValue
    var codingPath: [any CodingKey] { [] }

    func decodeNil() -> Bool { value == .null }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let raw) = value else { throw mismatch(Bool.self) }
        return raw
    }

    func decode(_ type: String.Type) throws -> String {
        guard case .string(let raw) = value else { throw mismatch(String.self) }
        return raw
    }

    func decode(_ type: Double.Type) throws -> Double {
        switch value {
        case .double(let raw): raw
        case .int(let raw): Double(raw)
        default: throw mismatch(Double.self)
        }
    }

    func decode(_ type: Float.Type) throws -> Float { Float(try decode(Double.self)) }
    func decode(_ type: Int.Type) throws -> Int { try integer() }
    func decode(_ type: Int8.Type) throws -> Int8 { try narrowed() }
    func decode(_ type: Int16.Type) throws -> Int16 { try narrowed() }
    func decode(_ type: Int32.Type) throws -> Int32 { try narrowed() }
    func decode(_ type: Int64.Type) throws -> Int64 { try narrowed() }
    func decode(_ type: UInt.Type) throws -> UInt { try narrowed() }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try narrowed() }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try narrowed() }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try narrowed() }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try narrowed() }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: ProbeDecoder(value: value))
    }

    private func integer() throws -> Int {
        guard case .int(let raw) = value else { throw mismatch(Int.self) }
        return raw
    }

    private func narrowed<T: FixedWidthInteger>() throws -> T {
        let raw = try integer()
        guard let narrowed = T(exactly: raw) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "\(raw) does not fit in \(T.self)"
                )
            )
        }
        return narrowed
    }

    private func mismatch(_ type: Any.Type) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected \(type) but the probe holds \(value)"
            )
        )
    }
}
