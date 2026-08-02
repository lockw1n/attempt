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
// What it covers. Every type in this module encodes as a *single value* — `Weight` is a bare
// integer of grams, `RoundingStrategy` a bare string, `DisplayPrecision` a bare integer. So the
// probe implements the single-value path for real and traps on the keyed and unkeyed paths: a
// type that reaches for one of those has changed its wire format, and the failure should be loud.
// Extend this rather than reaching for Foundation when T-0.12 or T-0.20 need composite shapes.

/// One encoded primitive — the entire vocabulary this module's wire formats use.
enum ProbeValue: Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case string(String)
    case double(Double)
    case int(Int)

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): "bool(\(value))"
        case .string(let value): "string(\"\(value)\")"
        case .double(let value): "double(\(value))"
        case .int(let value): "int(\(value))"
        }
    }
}

/// Raised when a probed type uses part of the `Codable` surface this probe deliberately omits.
struct ProbeUnsupported: Error, CustomStringConvertible {
    let what: String
    var description: String { "CodableProbe does not support \(what)" }
}

// MARK: - Encoding

/// Encodes `value` and returns the single primitive it wrote.
///
/// - Throws: `ProbeUnsupported` if `value` writes a keyed or unkeyed container, or a primitive
///   outside `ProbeValue`'s vocabulary.
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
}

struct ProbeEncoder: Encoder {
    let storage: ProbeStorage
    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        preconditionFailure("CodableProbe does not support keyed encoding")
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
        throw ProbeUnsupported(what: "keyed decoding")
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw ProbeUnsupported(what: "unkeyed decoding")
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        ProbeSingleValueDecodingContainer(value: value)
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
