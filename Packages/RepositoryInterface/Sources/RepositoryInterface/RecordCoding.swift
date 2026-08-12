// The wire format every record shares (TR-0.4.4, TR-5.4, FR-1.11.3). Stated once here rather than
// nine times, and the two helpers below are the only mechanism any of the nine uses.
//
// 1. KEYS ARE THE PROPERTY NAMES, DECLARED RATHER THAN SYNTHESISED. Every conformance declares
//    `CodingKeys` and hand-writes both halves, as `RoundingRule` and `SetRecord` do, so the
//    spelling is a decision rather than a side effect of how the properties happen to be named.
//    Renaming a property is therefore not a rename. The spellings are pinned by assertion in
//    `RecordCodingTests`.
//
//    KEY ORDER IS NOT A WIRE CONTRACT HERE, AND THAT IS A MEASUREMENT RATHER THAN AN OMISSION.
//    Both halves are still written in declaration order, because a reader comparing the two has
//    to be able to line them up — but `JSONEncoder` accumulates a keyed container into a
//    dictionary and emits it in Swift's per-process hash order, which differs between runs of the
//    same binary. So the order these methods write in is not the order the bytes carry, and an
//    assertion on it through a real encoder is flaky rather than strict. A byte-stable payload
//    needs an encoder that fixes an order (`.sortedKeys` is the cheap one) and choosing it is the
//    same decision as choosing the date strategy below: TR-2.1's and TR-5.4's, not this layer's.
//
// 2. NESTED FORMATS BELONG TO THE NESTED TYPE AND ARE NOT RE-WRAPPED. A `Weight` is a bare integer
//    of grams — 102500, never {"grams": 102500} — and a `SetModifier` a bare string. Those are
//    PowerliftingCore's pinned formats and this layer inherits them rather than restating them.
//
// 3. AN OPTIONAL IS OMITTED WHEN nil, NEVER WRITTEN AS null. Both forms decode; only omission is
//    produced. Same rule `SetRecord` already follows, so a record and the domain type it projects
//    to do not disagree about what an absent field looks like.
//
// 4. A VOCABULARY COLUMN IS A BARE RAW STRING AND DECODING ONE NEVER THROWS. It resolves through
//    `RecordVocabulary`, which is the same table the stored mapping reads — so a row arriving from
//    a newer version resolves identically whether it came through the store or through a backup
//    file. This is rule 4 of the module header applied to the wire: an unreadable field costs that
//    field and never the row. `SetEntry.modifiers` is the exception and does not route through the
//    table at all; it preserves verbatim, because nothing re-supplies a modifier the user typed.
//
// 5. EVERYTHING ELSE STILL THROWS. A string where an integer belongs, or a missing non-optional
//    key, is corruption rather than a newer vocabulary, and a record that invented a value for it
//    would be a backup that cannot be told from a good one.
//
// 6. A RECORD VALIDATES NOTHING ON DECODE. Unlike `SetRecord` and `RoundingRule`, whose decoders
//    re-run their initialisers' guards, these carry a stored row's values whatever they are — that
//    is the whole of T-0.40's mirror-the-row decision, and a decoder that refused would be a backup
//    format that cannot carry the rows a repair exists for. The refusals live in `Projections.swift`.
//    `SetEntry`'s modifier canonicalisation is not validation and does run: it rejects nothing and
//    alters no spelling, and without it the format would admit two encodings of one set.
//
// The DATE representation is deliberately NOT pinned here. It is whatever the encoder in use is
// configured for, because choosing one is choosing a wire format for Phase 2's blob (TR-2.1) and
// Phase 5's sync payload (TR-5.4), and neither exists yet. What is pinned is that a date is written
// as a single value under its own key.

import Foundation
import PowerliftingCore

extension KeyedDecodingContainer {
    /// Decodes a vocabulary column, resolving an unrecognised spelling to `fallback`.
    ///
    /// Throws only when the key is absent or does not hold a string. See rule 4 above.
    func decodeVocabulary<T>(
        _ type: T.Type, forKey key: Key, or fallback: RecordVocabulary.Fallback<T>
    ) throws -> T {
        RecordVocabulary.resolve(try decode(String.self, forKey: key), or: fallback)
    }
}

extension KeyedEncodingContainer {
    /// Writes a vocabulary value as its bare raw string. See rule 4 above.
    mutating func encodeVocabulary<T>(_ value: T, forKey key: Key) throws
    where T: RawRepresentable, T.RawValue == String {
        try encode(value.rawValue, forKey: key)
    }
}
