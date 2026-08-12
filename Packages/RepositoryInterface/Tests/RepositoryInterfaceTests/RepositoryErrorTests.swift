import Foundation
import RepositoryInterface
import Testing

@Suite("Repository refusals")
struct RepositoryErrorTests {
    // Every case carries a UUID, so an Equatable conformance keyed on the payload alone would make
    // three different refusals compare equal — and a caller distinguishing "this row is not there"
    // from "the row it points at is not there" would silently take the wrong branch. Three
    // directions asserted: same case with a different payload, the same payload under a different
    // case, and — the one a mutation probe found missing — two `danglingReference`s that agree on
    // `recordID` and differ only in what they point at. The first draft varied both payloads at
    // once, so a conformance reading only the first would have passed it.
    @Test("Refusals are distinguished by their case as well as by every payload")
    func refusalsAreDistinguishable() {
        let one = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001") ?? UUID()
        let two = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002") ?? UUID()
        let three = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003") ?? UUID()

        #expect(RepositoryError.recordNotFound(id: one) != .recordNotFound(id: two))
        #expect(RepositoryError.recordNotFound(id: one) != .identityAlreadyEstablished(recordID: one))
        #expect(
            RepositoryError.danglingReference(recordID: one, referencing: two)
                != .danglingReference(recordID: one, referencing: three)
        )
        #expect(
            RepositoryError.danglingReference(recordID: one, referencing: two)
                != .danglingReference(recordID: three, referencing: two)
        )
        #expect(RepositoryError.recordNotFound(id: one) == .recordNotFound(id: one))
    }
}
