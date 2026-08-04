/// One logged set: what was lifted, for how many reps, how hard it felt, and under what
/// conditions (`TR-0.2.3`).
///
/// This is the *analytical* value type — the input every formula in this package takes. It is not
/// a mirror of `SetEntryEntity` (`TR-0.3.4`), which additionally carries identity, ordering, the
/// prescription that produced the set, a timestamp and a per-set note. Those are the storage
/// layer's business; this type holds exactly the seven fields `TR-0.2.3` names, because those are
/// the ones e1RM (`TR-0.2.5`) and personal records (`TR-0.2.8`) read.
///
/// **``isWarmup`` and ``isCompleted`` are not optional and have no defaults** (`G-1.8`). Analytics
/// correctness depends on them and they cannot be backfilled: a set logged before the flags exist
/// is permanently ambiguous, and no later migration can recover whether it was a warmup. Requiring
/// them at every call site is the cheapest available guard against that.
///
/// Value semantics throughout — every property is a `let`, and the only reference type anywhere in
/// the graph is none at all.
public struct SetRecord: Sendable, Hashable, Codable {
    /// The load on **one implement**, as the lifter reads it off the equipment.
    ///
    /// **This convention is a permanent storage contract and cannot be re-derived from the number
    /// later.** `Laterality` deliberately answers only whether a rep count covers the whole body
    /// or one side; it does not answer this, and T-0.12 decides it here so that the first dumbbell
    /// exercise does not decide it by accident. Concretely:
    ///
    /// - A barbell squat is the whole bar — bar, plates and collars together. "I squatted 140 kg"
    ///   means the number on the bar, so `weight` is 140 000 g.
    /// - A two-dumbbell bench press with 40 kg dumbbells is **40 kg**, not 80. One implement.
    /// - A single-arm row with a 40 kg dumbbell is 40 kg. One implement, and `Laterality`
    ///   separately records that the reps are per side.
    ///
    /// The reason is entry safety: the number the user types has to be the number printed on the
    /// equipment, because any other convention invites a silent 2× error at the moment of logging
    /// and `G-1.6` forbids the app from quietly rewriting it afterwards. Per-exercise records
    /// (`TR-0.2.8`) are unaffected either way — they never compare across exercises.
    ///
    /// **Tonnage (`FR-1.5.1`) is the thing this costs, and it is not solvable in Phase 0.** Total
    /// work is `weight × reps × implements × sides`, and neither factor is derivable from what the
    /// schema records: a two-dumbbell bench and a barbell bench are both `Laterality.bilateral`
    /// but move one implement versus two, while a goblet squat is `bilateral` with a single
    /// dumbbell. So `Equipment` plus `Laterality` is not enough. Recorded as gap §9 of the Phase 0
    /// coverage matrix and carried into T-0.31, T-0.51 and T-0.18.
    ///
    /// **May be negative.** `Weight` is signed, and a band- or machine-assisted bodyweight set is
    /// the case that needs it: an assisted pull-up is genuinely a negative *added* load. Enforcing
    /// non-negativity here would make that unloggable, so the range is any `Int` of grams.
    public let weight: Weight

    /// Repetitions actually performed. At least zero.
    ///
    /// Zero is legal and meaningful: `FR-1.2.5` says a failed set records the reps actually
    /// achieved, and that can be none. Negative is rejected — it has no reading, and it would
    /// silently corrupt tonnage and rep-max maths downstream.
    ///
    /// For a `Laterality.unilateral` exercise this is reps *per side*, per that type's contract.
    public let reps: Int

    /// Rating of Perceived Exertion, or `nil` when the lifter did not record one (`FR-1.2.3`).
    ///
    /// Valid range is ``rpeRange`` — 1 through 10 inclusive — and that bound *is* enforced, at the
    /// initialiser and when decoding. The scale is defined as running from 1 to 10, so a value
    /// outside it is corruption rather than a newer convention.
    ///
    /// **The 0.5 step is a convention and is deliberately not enforced.** Entry is conventionally
    /// in half points (8, 8.5, 9), but nothing here rejects 8.25: the step is a UI choice, and
    /// throwing on a finer-grained value from a newer version would cost the whole set record for
    /// the sake of one field. `Double.nan` is outside the range and therefore rejected, which also
    /// keeps ``Hashable`` well-behaved.
    ///
    /// See ``rir`` for the relationship between the two, which is documented but not enforced.
    public let rpe: Double?

    /// Reps In Reserve, or `nil` when the lifter did not record one.
    ///
    /// Valid range is ``rirRange`` — 0 through 9 inclusive — enforced at the initialiser and when
    /// decoding. The bound is derived from ``rpeRange`` rather than chosen: RIR and RPE are two
    /// spellings of one scale, related by `rir = 10 - rpe`, so an RPE floor of 1 puts the RIR
    /// ceiling at 9.
    ///
    /// **Both may be set at once, and they are not required to agree.** `TR-0.2.3` and `TR-0.3.4`
    /// both list them as independent optional fields, so the schema expects both to exist; forcing
    /// consistency would mean the app rewriting one of them, which `G-1.6` forbids for logged
    /// data. Which one wins when they disagree is a question for the RPE-based formula (T-0.15),
    /// not for storage, and that task's file carries it.
    public let rir: Int?

    /// Whether this set was a warmup rather than working (`G-1.8`, `FR-1.2.4`).
    ///
    /// Non-optional with no default: see the type's note. `E1RMCalculator` (`TR-0.2.5`) and the
    /// personal-record calculator (`TR-0.2.8`) both exclude warmups, so a wrong value here is a
    /// wrong number on the dashboard rather than a cosmetic slip.
    public let isWarmup: Bool

    /// Whether the set was completed as intended (`G-1.8`, `FR-1.2.5`).
    ///
    /// Non-optional with no default: see the type's note. `false` marks a failed set — which still
    /// records the ``reps`` actually achieved, so the two fields are independent.
    public let isCompleted: Bool

    /// Conditions the set was performed under, deduplicated and in a canonical order
    /// (`FR-1.2.8`).
    ///
    /// **Stored as an `Array`, not a `Set`, and canonicalised on the way in.** A `Set` iterates in
    /// a nondeterministic order, so its encoding is not byte-stable and the wire format could not
    /// be pinned the way every other composite shape in this module is. A raw `Array` is stable
    /// but would admit duplicates and a meaningless order. So the initialiser removes duplicates
    /// and sorts by raw spelling: equality then matches meaning — belt+sleeves equals
    /// sleeves+belt — and the bytes are the same every time. Decoding canonicalises too, so a
    /// payload written by hand or by a newer version normalises rather than round-tripping
    /// unstably.
    ///
    /// The sort is by ``OpenVocabulary/rawValue`` and is therefore not a display order. Sorting
    /// for a user is a localisation concern, which is Foundation, which this package may not
    /// import (`NFR-0.2`); the UI layer orders what it shows.
    ///
    /// One limit on "the same set of modifiers always encodes the same bytes": deduplication uses
    /// ``OpenVocabulary``'s equality, which is `String`'s, which is canonical equivalence. Two
    /// spellings that differ only in Unicode normalisation are one modifier here, and the one that
    /// survives is whichever came first — so two equal records can encode differently. Reachable
    /// only through a user-configured modifier (`FR-1.2.8`); see ``OpenVocabulary`` for why it is
    /// accepted rather than fixed. Encode → decode → encode is stable regardless.
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
    /// Failable rather than trapping, and failable rather than clamping, for the same reason
    /// `RoundingRule`'s initialiser is: the boundary belongs at construction, where a caller can
    /// still report the problem, rather than inside a formula that has no way to.
    ///
    /// - Parameters:
    ///   - weight: The load on one implement — see ``weight`` for what that means for dumbbells.
    ///     Any value, including negative.
    ///   - reps: Reps actually performed. Must be at least zero.
    ///   - rpe: Rating of Perceived Exertion, 1 through 10, or `nil`.
    ///   - rir: Reps In Reserve, 0 through 9, or `nil`.
    ///   - isWarmup: Whether the set was a warmup. No default, on purpose (`G-1.8`).
    ///   - isCompleted: Whether the set was completed. No default, on purpose (`G-1.8`).
    ///   - modifiers: Conditions the set was performed under. Deduplicated and sorted by raw
    ///     spelling; the order passed in is not preserved.
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

    /// `modifiers` with duplicates removed and sorted by raw spelling.
    ///
    /// Going through a `Set` is what removes duplicates; sorting afterwards is what makes the
    /// result deterministic despite that. See ``modifiers``.
    static func canonicalised(_ modifiers: [SetModifier]) -> [SetModifier] {
        Set(modifiers).sorted { $0.rawValue < $1.rawValue }
    }
}

// MARK: - Codable

extension SetRecord {
    /// The wire format's keys, in the order they are written.
    ///
    /// The shape is
    /// `{"weight": 102500, "reps": 5, "rpe": 8.5, "rir": 1, "isWarmup": false, "isCompleted": true,
    /// "modifiers": ["belt", "sleeves"]}` — `weight` is a bare integer of grams because that is
    /// `Weight`'s pinned single-value format, and each modifier is a bare string because that is
    /// ``OpenVocabulary``'s. Declared rather than synthesised so the spelling and the order are
    /// decisions rather than side effects, following `RoundingRule`'s precedent (T-0.13).
    ///
    /// **``rpe`` and ``rir`` are omitted entirely when `nil`**, rather than written as `null`. Both
    /// forms decode; only the omission is produced. `modifiers` is always written, as `[]` when
    /// empty — it is not optional, and an absent-versus-empty distinction would carry no meaning.
    private enum CodingKeys: String, CodingKey {
        case weight
        case reps
        case rpe
        case rir
        case isWarmup
        case isCompleted
        case modifiers
    }

    /// Decodes the keyed shape described on ``CodingKeys``, enforcing the same ranges as
    /// ``init(weight:reps:rpe:rir:isWarmup:isCompleted:modifiers:)``.
    ///
    /// Hand-written for the reason `RoundingRule`'s is: synthesised `Decodable` bypasses the
    /// failable initialiser, so a payload carrying an RPE of 47 or a negative rep count would
    /// become a `SetRecord` that every formula downstream then has to defend against. Each range
    /// violation throws keyed to the field that caused it, so the error names the problem.
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

    /// Writes the seven keys in declaration order.
    ///
    /// Hand-written so the order is a decision rather than a side effect of synthesis: byte
    /// stability of a keyed shape is key order plus key spelling, and `NFR-2.3` rests on it. Both
    /// are pinned by test.
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
