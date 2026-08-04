// The encoding half of `CodableProbe` — see `CodableProbe.swift` for what this exists for and
// what it deliberately does not cover. Split out of that file in T-0.12, when adding the unkeyed
// (array) containers took the single file past SwiftLint's 500-line ceiling.

/// Encodes `value` and returns the `ProbeValue` it wrote — a primitive, an object, or an array.
///
/// - Throws: `ProbeUnsupported` if `value` encodes nothing at all, or writes a primitive outside
///   `ProbeValue`'s vocabulary. Asking for an explicitly *nested* container is a
///   `preconditionFailure` rather than a throw, because there is no container to return in its
///   place.
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
    private var array: ProbeArrayStorage?

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

    /// The array accumulator for this slot, created once and then reused.
    ///
    /// Same rule and same trap as ``objectStorage()``: `Encoder.unkeyedContainer()` may be called
    /// more than once for a single value, and a fresh accumulator per call would drop everything
    /// appended through the earlier one. Built this way from the start in T-0.12 because the keyed
    /// path had already paid for the lesson; `CodableProbeTests` pins both halves.
    func arrayStorage() -> ProbeArrayStorage {
        if let array { return array }
        let created = ProbeArrayStorage(parent: self)
        array = created
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
        ProbeUnkeyedEncodingContainer(array: storage.arrayStorage())
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

/// Accumulates an array's elements and writes the growing value through to its parent.
///
/// The array counterpart of ``ProbeObjectStorage``, with the same write-through-on-append: the
/// parent holds a complete `.array` even if the encoding stops early.
final class ProbeArrayStorage {
    private let parent: ProbeStorage
    private var elements: [ProbeValue] = []

    var count: Int { elements.count }

    init(parent: ProbeStorage) {
        self.parent = parent
        parent.value = .array([])
    }

    func append(_ element: ProbeValue) {
        elements.append(element)
        parent.value = .array(elements)
    }
}

struct ProbeUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let array: ProbeArrayStorage
    var codingPath: [any CodingKey] { [] }
    var count: Int { array.count }

    mutating func encodeNil() throws { try write { try $0.encodeNil() } }
    mutating func encode(_ value: Bool) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: String) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: Double) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: Float) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: Int) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: Int8) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: Int16) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: Int32) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: Int64) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: UInt) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: UInt8) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: UInt16) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: UInt32) throws { try write { try $0.encode(value) } }
    mutating func encode(_ value: UInt64) throws { try write { try $0.encode(value) } }

    mutating func encode<T: Encodable>(_ value: T) throws {
        try write { try $0.encode(value) }
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        // Unreachable through `encode(_:)`, which nests by re-entering `ProbeEncoder`; see the
        // matching note on `ProbeKeyedEncodingContainer.nestedContainer(keyedBy:forKey:)`.
        preconditionFailure("CodableProbe does not support explicitly nested keyed encoding")
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        preconditionFailure("CodableProbe does not support explicitly nested unkeyed encoding")
    }

    func superEncoder() -> any Encoder {
        preconditionFailure("CodableProbe does not support class inheritance")
    }

    /// Encodes one element through a fresh single-value container and appends the result.
    ///
    /// Routing each element back through `ProbeSingleValueEncodingContainer` is what lets an array
    /// hold anything the probe can encode — a bare string for a `SetModifier`, an object for a
    /// composite — without this container knowing which.
    private func write(_ body: (ProbeSingleValueEncodingContainer) throws -> Void) throws {
        let storage = ProbeStorage()
        try body(ProbeSingleValueEncodingContainer(storage: storage))
        guard let encoded = storage.value else {
            throw ProbeUnsupported(what: "an array element that encoded nothing")
        }
        array.append(encoded)
    }
}
