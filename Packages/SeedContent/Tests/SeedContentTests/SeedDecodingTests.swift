import Testing

@testable import SeedContent

// The two decode-time guarantees that no fixture can reach. `JSONDecoder` hands `allKeys` over
// already sorted and spells an array index `Index 0`, so a payload exercises neither the sort nor
// the index rendering against an input that could distinguish them. Measured, not assumed: a probe
// replacing `.min()` with `.first` survives all twenty fixtures.

@Suite("Decode-time guarantees")
struct SeedDecodingTests {
    private let declared: Set<String> = ["schemaVersion", "revision", "exercises"]

    @Test("The reported key is the sorted-first unrecognised one, whatever order they arrive in")
    func unrecognisedKeyIsSortedFirst() {
        // The two orders disagree on which key comes first, which is the whole point: a pick that
        // took the input's own order would answer differently for the two.
        #expect(unrecognisedKey(among: ["version", "edition"], declared: declared) == "edition")
        #expect(unrecognisedKey(among: ["edition", "version"], declared: declared) == "edition")
    }

    @Test("A declared key is never reported, however many there are")
    func declaredKeysAreNotReported() {
        #expect(unrecognisedKey(among: Array(declared), declared: declared) == nil)
        #expect(unrecognisedKey(among: [], declared: declared) == nil)
        // Anchored to a literal rather than to another `nil`: the refusal above is only meaningful
        // if this call can return something.
        #expect(unrecognisedKey(among: Array(declared) + ["edition"], declared: declared) == "edition")
    }

    @Test("A location reads the way an author would search for it")
    func locationRendersAsAPath() {
        #expect(seedLocation(of: []).isEmpty)
        #expect(seedLocation(of: [AnyCodingKey(stringValue: "exercises")]) == "exercises")
        #expect(seedLocation(of: [ArrayIndexKey(index: 3)]) == "[3]")
        #expect(
            seedLocation(
                of: [
                    AnyCodingKey(stringValue: "exercises"), ArrayIndexKey(index: 3),
                    AnyCodingKey(stringValue: "id"),
                ]) == "exercises[3].id")
    }
}

/// The shape a decoder uses for an array element: a key carrying an `intValue`.
private struct ArrayIndexKey: CodingKey {
    let index: Int
    var stringValue: String { "Index \(index)" }
    var intValue: Int? { index }

    init(index: Int) {
        self.index = index
    }

    init?(stringValue: String) {
        nil
    }

    init?(intValue: Int) {
        self.init(index: intValue)
    }
}
