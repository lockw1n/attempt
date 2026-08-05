/// One logged set: what was lifted, for how many reps, how hard it felt, and under what
/// conditions (`TR-0.2.3`).
///
/// The *analytical* value type — the input every formula in this package takes. It is not a mirror
/// of `SetEntryEntity` (`TR-0.3.4`), which also carries identity, ordering, the prescription that
/// produced the set, a timestamp and a per-set note. This holds exactly the seven fields
/// `TR-0.2.3` names, because those are what e1RM (`TR-0.2.5`) and personal records (`TR-0.2.8`)
/// read.
///
/// **``isWarmup`` and ``isCompleted`` are not optional and have no defaults** (`G-1.8`). A set
/// logged before those flags exist is permanently ambiguous and no migration can recover it, so
/// requiring them at every call site is the cheapest guard available. Do not add defaults.
public struct SetRecord: Sendable, Hashable, Codable {
    /// The load on **one implement**, as the lifter reads it off the equipment.
    ///
    /// **A permanent storage contract that cannot be re-derived from the number later.**
    /// ``Laterality`` answers only whether a rep count covers the whole body or one side, not this.
    ///
    /// - A barbell squat is the whole bar — bar, plates and collars. 140 kg squatted is 140 000 g.
    /// - A two-dumbbell bench press with 40 kg dumbbells is **40 kg**, not 80. One implement.
    /// - A single-arm row with a 40 kg dumbbell is 40 kg; ``Laterality`` separately records that
    ///   the reps are per side.
    ///
    /// The reason is entry safety: the number the user types has to be the number printed on the
    /// equipment, because any other convention invites a silent 2× error at logging time and
    /// `G-1.6` forbids rewriting it afterwards. Tonnage (`FR-1.5.1`) is what this costs — total
    /// work needs an implement count that the schema does not record — and is unresolved.
    ///
    /// **May be negative.** A band- or machine-assisted bodyweight set is genuinely a negative
    /// *added* load, so enforcing non-negativity here would make an assisted pull-up unloggable.
    public let weight: Weight

    /// Repetitions actually performed. At least zero.
    ///
    /// Zero is legal and meaningful: `FR-1.2.5` says a failed set records the reps actually
    /// achieved, which can be none. Negative is rejected — it has no reading and would corrupt
    /// tonnage and rep-max maths downstream. For a `Laterality.unilateral` exercise this is reps
    /// *per side*.
    public let reps: Int

    /// Rating of Perceived Exertion, or `nil` when the lifter did not record one (`FR-1.2.3`).
    ///
    /// ``rpeRange`` — 1 through 10 — is enforced at the initialiser and when decoding, because the
    /// scale is defined over that interval, so a value outside it is corruption.
    ///
    /// **The 0.5 step is a convention and deliberately not enforced.** Entry is conventionally in
    /// half points, but 8.25 is accepted: the step is a UI choice, and throwing on a finer value
    /// from a newer version would cost the whole record for one field. `Double.nan` falls outside
    /// the range and is therefore rejected, which also keeps ``Hashable`` well-behaved.
    public let rpe: Double?

    /// Reps In Reserve, or `nil` when the lifter did not record one.
    ///
    /// ``rirRange`` — 0 through 9 — is enforced, and derived rather than chosen: RIR and RPE are
    /// two spellings of one scale related by `rir = 10 - rpe`, so an RPE floor of 1 puts the RIR
    /// ceiling at 9.
    ///
    /// **Both may be set at once and are not required to agree.** `TR-0.2.3` and `TR-0.3.4` list
    /// them as independent optional fields, and forcing consistency would mean rewriting logged
    /// data, which `G-1.6` forbids. Which one wins when they disagree is the RPE-based formula's
    /// question, not storage's.
    public let rir: Int?

    /// Whether this set was a warmup rather than working (`G-1.8`, `FR-1.2.4`).
    ///
    /// Non-optional with no default — see the type's note. `TR-0.2.5` and `TR-0.2.8` both exclude
    /// warmups, so a wrong value here is a wrong number on the dashboard.
    public let isWarmup: Bool

    /// Whether the set was completed as intended (`G-1.8`, `FR-1.2.5`).
    ///
    /// Non-optional with no default — see the type's note. `false` marks a failed set, which still
    /// records the ``reps`` achieved, so the two fields are independent.
    public let isCompleted: Bool

    /// Conditions the set was performed under, deduplicated and in a canonical order (`FR-1.2.8`).
    ///
    /// **Stored as an `Array`, not a `Set`, and canonicalised on the way in.** A `Set` iterates
    /// nondeterministically, so its encoding could not be pinned; a raw `Array` would admit
    /// duplicates and a meaningless order. Deduplicating and sorting by raw spelling makes equality
    /// match meaning — belt+sleeves equals sleeves+belt — and the bytes identical every time.
    /// Decoding canonicalises too.
    ///
    /// The sort is by ``OpenVocabulary/rawValue``, so it is **not** a display order: sorting for a
    /// user is localisation, which is Foundation, which this package may not import (`NFR-0.2`).
    ///
    /// Deduplication inherits ``OpenVocabulary``'s Unicode caveat, so two equal records can encode
    /// differently; encode → decode → encode is stable regardless.
    public let modifiers: [SetModifier]

    /// The closed range a valid ``rpe`` falls in — 1 through 10.
    public static let rpeRange: ClosedRange<Double> = 1...10

    /// The closed range a valid ``rir`` falls in — 0 through 9. Derived from ``rpeRange`` by
    /// `rir = 10 - rpe`.
    public static let rirRange: ClosedRange<Int> = 0...9

    /// The closed range a valid ``reps`` falls in — zero upwards.
    public static let repsRange: ClosedRange<Int> = 0...Int.max

    /// Creates a logged set, or returns `nil` if any field is outside its documented range.
    ///
    /// Failable rather than trapping or clamping: the boundary belongs at construction, where a
    /// caller can still report the problem, rather than inside a formula that cannot.
    ///
    /// - Parameters:
    ///   - weight: The load on one implement — see ``weight``. Any value, including negative.
    ///   - reps: Reps actually performed. Must be at least zero.
    ///   - rpe: Rating of Perceived Exertion, 1 through 10, or `nil`.
    ///   - rir: Reps In Reserve, 0 through 9, or `nil`.
    ///   - isWarmup: No default, on purpose (`G-1.8`).
    ///   - isCompleted: No default, on purpose (`G-1.8`).
    ///   - modifiers: Deduplicated and sorted by raw spelling; input order is not preserved.
    /// - Returns: `nil` if `reps` is negative, or if `rpe` or `rir` is present and out of range.
    public init?(
        weight: Weight,
        reps: Int,
        rpe: Double? = nil,
        rir: Int? = nil,
        isWarmup: Bool,
        isCompleted: Bool,
        modifiers: [SetModifier] = []
    ) {
        guard Self.repsRange.contains(reps) else { return nil }
        if let rpe, !Self.rpeRange.contains(rpe) { return nil }
        if let rir, !Self.rirRange.contains(rir) { return nil }
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.isWarmup = isWarmup
        self.isCompleted = isCompleted
        self.modifiers = Self.canonicalised(modifiers)
    }

    /// `modifiers` with duplicates removed and sorted by raw spelling. See ``modifiers``.
    static func canonicalised(_ modifiers: [SetModifier]) -> [SetModifier] {
        Set(modifiers).sorted { $0.rawValue < $1.rawValue }
    }
}

// MARK: - Codable

extension SetRecord {
    /// The wire format's keys, in the order they are written:
    /// `{"weight": 102500, "reps": 5, "rpe": 8.5, "rir": 1, "isWarmup": false, "isCompleted": true,
    /// "modifiers": ["belt", "sleeves"]}`. `weight` is a bare integer of grams and each modifier a
    /// bare string, those being `Weight`'s and ``OpenVocabulary``'s pinned formats.
    ///
    /// **``rpe`` and ``rir`` are omitted entirely when `nil`**, not written as `null`; both forms
    /// decode, only omission is produced. `modifiers` is always written, as `[]` when empty.
    private enum CodingKeys: String, CodingKey {
        case weight
        case reps
        case rpe
        case rir
        case isWarmup
        case isCompleted
        case modifiers
    }

    /// Decodes the keyed shape on ``CodingKeys``, enforcing the same ranges as the initialiser.
    ///
    /// Hand-written because synthesised `Decodable` would bypass the failable initialiser, so a
    /// payload carrying an RPE of 47 or a negative rep count would become a `SetRecord` every
    /// formula downstream then has to defend against. Each violation throws keyed to its field.
    ///
    /// `modifiers` never fails on an unrecognised spelling — see ``SetModifier``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let reps = try container.decode(Int.self, forKey: .reps)
        guard Self.repsRange.contains(reps) else {
            throw DecodingError.dataCorruptedError(
                forKey: .reps,
                in: container,
                debugDescription: "SetRecord reps must be at least 0, got \(reps).")
        }
        let rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        if let rpe, !Self.rpeRange.contains(rpe) {
            throw DecodingError.dataCorruptedError(
                forKey: .rpe,
                in: container,
                debugDescription: "SetRecord rpe must be within \(Self.rpeRange), got \(rpe).")
        }
        let rir = try container.decodeIfPresent(Int.self, forKey: .rir)
        if let rir, !Self.rirRange.contains(rir) {
            throw DecodingError.dataCorruptedError(
                forKey: .rir,
                in: container,
                debugDescription: "SetRecord rir must be within \(Self.rirRange), got \(rir).")
        }

        self.weight = try container.decode(Weight.self, forKey: .weight)
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.isWarmup = try container.decode(Bool.self, forKey: .isWarmup)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.modifiers = Self.canonicalised(try container.decode([SetModifier].self, forKey: .modifiers))
    }

    /// Writes the seven keys in declaration order. Hand-written so the order is a decision rather
    /// than a side effect of synthesis; `NFR-2.3` rests on it, and both order and spelling are
    /// pinned by test.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weight, forKey: .weight)
        try container.encode(reps, forKey: .reps)
        try container.encodeIfPresent(rpe, forKey: .rpe)
        try container.encodeIfPresent(rir, forKey: .rir)
        try container.encode(isWarmup, forKey: .isWarmup)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(modifiers, forKey: .modifiers)
    }
}
