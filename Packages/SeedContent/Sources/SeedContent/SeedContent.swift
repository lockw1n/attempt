// SeedContent — the schema of the bundled and published content payloads, and the validator that
// gates them (`TR-0.5.1`).
//
// Module-wide rules, stated once here:
//
//   - THE PAYLOAD IS NOT A STORAGE RECORD. It carries what a catalogue author writes and nothing
//     else: no audit columns, no `isCustom`, no `isArchived`, no notes. The importer supplies those.
//     `TR-0.5.2` serves this same file from a CDN, so its shape is a public contract with a longer
//     life than any schema version.
//
//   - THE VOCABULARIES ARE NEVER RESTATED. `SeedVocabularyField` resolves through
//     `Movement`, `Equipment`, `Laterality` and `BarType`, and derives its accepted-value lists from
//     their `CaseIterable` conformances. A second copy of those lists is how the validator and the
//     types drift apart.
//
//   - VALIDATION IS NOT DECODING, and here that is a correctness rule rather than a layering
//     preference. Three of the four vocabularies resolve an unrecognised spelling to `.other` on
//     decode, deliberately — so a validator built on `Decodable` accepts `"sled"` silently and
//     passes the fixture written to fail it. Every vocabulary field is decoded as a `String` and
//     checked with `init?(rawValue:)`.
//
//   - THE TYPES DECODE ONLY. Nothing writes this file: it is authored by hand and published as
//     bytes. An `Encodable` conformance would invite a round-trip assertion that pins nothing,
//     because `JSONEncoder` emits keys in per-process hash order.
