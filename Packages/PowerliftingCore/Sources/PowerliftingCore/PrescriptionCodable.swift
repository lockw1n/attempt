// MARK: - The wire format

extension AnyCodingKey {
    /// The envelope: a schema version and a type discriminator, written first and in this order.
    static let version = AnyCodingKey("version")
    static let type = AnyCodingKey("type")

    /// Payload keys. Each case writes at most one, so the spellings are per-case rather than shared.
    static let weight = AnyCodingKey("weight")
    static let percentage = AnyCodingKey("percentage")
    static let rpe = AnyCodingKey("rpe")
    static let increment = AnyCodingKey("increment")
    static let added = AnyCodingKey("added")

    /// The two keys that belong to the envelope rather than to a prescription's payload. Reserved:
    /// no prescription type may use them for anything else, in this version or a later one.
    static let envelope: Set<String> = [version.stringValue, type.stringValue]
}

extension Prescription: Codable {
    /// Decodes the versioned object described on ``PrescriptionKind`` and the payload keys above —
    /// `{"version": 1, "type": "fixedWeight", "weight": 102500}`, with a nested ``Weight`` staying a
    /// bare integer of grams.
    ///
    /// **An unrecognised `type` is preserved rather than rejected or degraded** (`NFR-2.3`): the
    /// discriminator, the version and every payload key survive in
    /// ``Prescription/unrecognised(_:)``. A program is the user's own data and nothing re-supplies
    /// it, which is why this is the opposite of what ``Movement`` does with a value it does not know.
    ///
    /// **A recognised `type` is decoded whatever the version says**, including a version newer than
    /// ``currentSchemaVersion``. Refusing to read a `.fixedWeight` because the file said `2` would
    /// be the corruption `NFR-2.3` is about, not protection from it. What makes that safe is the
    /// rule on ``PrescriptionKind``: a spelling's meaning never changes. The cost is that keys added
    /// by a newer version to a type this one knows are dropped.
    ///
    /// Everything else throws. A missing or malformed envelope means this is not a prescription; a
    /// known type missing its own key is a corrupt payload rather than a newer vocabulary.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version >= 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Prescription schema version must be at least 1, got \(version).")
        }
        let type = try container.decode(String.self, forKey: .type)
        guard let kind = PrescriptionKind(rawValue: type) else {
            self = .unrecognised(
                UnrecognisedPrescription(
                    preservingKind: type,
                    schemaVersion: version,
                    payload: try Self.preservedPayload(from: container)))
            return
        }
        self = try Self.decoded(kind, from: container)
    }

    /// Writes the envelope and then this case's payload key, in that order.
    ///
    /// Hand-written so key order is a decision rather than a side effect of synthesis — byte
    /// stability of a keyed shape is spelling plus order, and `NFR-2.3` rests on it.
    /// ``unrecognised(_:)`` writes the version it arrived under rather than the current one.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        switch self {
        case .fixedWeight(let weight):
            try Self.encodeEnvelope(.fixedWeight, into: &container)
            try container.encode(weight, forKey: .weight)
        case .percentOfTrainingMax(let percentage):
            try Self.encodeEnvelope(.percentOfTrainingMax, into: &container)
            try container.encode(percentage, forKey: .percentage)
        case .percentOfE1RM(let percentage):
            try Self.encodeEnvelope(.percentOfE1RM, into: &container)
            try container.encode(percentage, forKey: .percentage)
        case .percentOfTopSet(let percentage):
            try Self.encodeEnvelope(.percentOfTopSet, into: &container)
            try container.encode(percentage, forKey: .percentage)
        case .rpeTarget(let rpe):
            try Self.encodeEnvelope(.rpeTarget, into: &container)
            try container.encode(rpe, forKey: .rpe)
        case .amrap:
            try Self.encodeEnvelope(.amrap, into: &container)
        case .previousPlusIncrement(let increment):
            try Self.encodeEnvelope(.previousPlusIncrement, into: &container)
            try container.encode(increment, forKey: .increment)
        case .bodyweight(let added):
            try Self.encodeEnvelope(.bodyweight, into: &container)
            try container.encode(added, forKey: .added)
        case .unrecognised(let preserved):
            try Self.encode(preserved, into: &container)
        }
    }

    /// The case named by `kind`, reading its one payload key. A missing key throws.
    private static func decoded(
        _ kind: PrescriptionKind, from container: KeyedDecodingContainer<AnyCodingKey>
    ) throws -> Prescription {
        switch kind {
        case .fixedWeight: .fixedWeight(try container.decode(Weight.self, forKey: .weight))
        case .percentOfTrainingMax:
            .percentOfTrainingMax(percentage: try container.decode(Double.self, forKey: .percentage))
        case .percentOfE1RM:
            .percentOfE1RM(percentage: try container.decode(Double.self, forKey: .percentage))
        case .percentOfTopSet:
            .percentOfTopSet(percentage: try container.decode(Double.self, forKey: .percentage))
        case .rpeTarget: .rpeTarget(rpe: try container.decode(Double.self, forKey: .rpe))
        case .amrap: .amrap
        case .previousPlusIncrement:
            .previousPlusIncrement(try container.decode(Weight.self, forKey: .increment))
        case .bodyweight: .bodyweight(added: try container.decode(Weight.self, forKey: .added))
        }
    }

    /// Every key of the object except the envelope's, held as-is.
    private static func preservedPayload(
        from container: KeyedDecodingContainer<AnyCodingKey>
    ) throws -> [String: PreservedValue] {
        var payload: [String: PreservedValue] = [:]
        for key in container.allKeys where !AnyCodingKey.envelope.contains(key.stringValue) {
            payload[key.stringValue] = try container.decode(PreservedValue.self, forKey: key)
        }
        return payload
    }

    private static func encodeEnvelope(
        _ kind: PrescriptionKind, into container: inout KeyedEncodingContainer<AnyCodingKey>
    ) throws {
        try container.encode(currentSchemaVersion, forKey: .version)
        try container.encode(kind.rawValue, forKey: .type)
    }

    /// Writes a preserved prescription back: its own version, its own discriminator, then its
    /// payload sorted by key. Sorted because the order it arrived in is not recoverable from a
    /// decoder, and a canonical order is what makes re-encoding stable.
    private static func encode(
        _ preserved: UnrecognisedPrescription, into container: inout KeyedEncodingContainer<AnyCodingKey>
    ) throws {
        try container.encode(preserved.schemaVersion, forKey: .version)
        try container.encode(preserved.kind, forKey: .type)
        for (key, value) in preserved.payload.sorted(by: { $0.key < $1.key }) {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }
}
