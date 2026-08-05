// The decoding half of `CodableProbe` — see `CodableProbe.swift` for what this exists for and
// what it deliberately does not cover. Split out of that file in T-0.12, when adding the unkeyed
// (array) containers took the single file past SwiftLint's 500-line ceiling.

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
        guard case .array(let elements) = value else {
            throw DecodingError.typeMismatch(
                [Any].self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Expected an array but the probe holds \(value)"
                )
            )
        }
        return ProbeUnkeyedDecodingContainer(elements: elements)
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
        try ProbeDecoder(value: try field(key)).unkeyedContainer()
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

struct ProbeUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let elements: [ProbeValue]
    var codingPath: [any CodingKey] { [] }
    var count: Int? { elements.count }
    var isAtEnd: Bool { currentIndex >= elements.count }
    var currentIndex: Int = 0

    /// Consumes the element only when it is null, per `UnkeyedDecodingContainer`'s contract.
    mutating func decodeNil() throws -> Bool {
        guard try peek() == .null else { return false }
        currentIndex += 1
        return true
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try next().decode(type) }
    mutating func decode(_ type: String.Type) throws -> String { try next().decode(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try next().decode(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try next().decode(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try next().decode(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try next().decode(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try next().decode(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try next().decode(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try next().decode(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try next().decode(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try next().decode(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try next().decode(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try next().decode(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try next().decode(type) }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: ProbeDecoder(value: try take()))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try ProbeDecoder(value: try take()).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try ProbeDecoder(value: try take()).unkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder {
        throw ProbeUnsupported(what: "class inheritance")
    }

    /// The element at ``currentIndex`` without consuming it.
    ///
    /// Running off the end is `valueNotFound` rather than a trap: an array shorter than the type
    /// expects is corrupt input, which a decoder is supposed to report, not crash the test run on.
    private func peek() throws -> ProbeValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                ProbeValue.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unkeyed container is at end after \(currentIndex) element(s)"
                )
            )
        }
        return elements[currentIndex]
    }

    /// The element at ``currentIndex``, consuming it.
    private mutating func take() throws -> ProbeValue {
        let element = try peek()
        currentIndex += 1
        return element
    }

    private mutating func next() throws -> ProbeSingleValueDecodingContainer {
        ProbeSingleValueDecodingContainer(value: try take())
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
