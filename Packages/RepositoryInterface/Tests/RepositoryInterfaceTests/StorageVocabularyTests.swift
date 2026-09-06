import RepositoryInterface
import Testing

// TR-0.2.2's rule one layer out: reordering a case must not rewrite history, so the persisted
// spellings of the four vocabularies this module declares are pinned to literals. Moved here from
// the Persistence suite with the types themselves — a storage contract's proof belongs beside the
// declaration it constrains, and the declaration is what a mapping reads.
@Suite("Storage vocabularies")
struct StorageVocabularyTests {
    @Test("The storage vocabularies persist as their spellings, not as ordinals")
    func storageVocabularySpellings() {
        #expect(BodyweightSource.allCases.map(\.rawValue) == ["manual", "healthKit"])
        #expect(ThemePreference.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(
            TrainingMaxSourceKind.allCases.map(\.rawValue) == [
                "percentOfE1RM", "percentOfRepMax", "manual",
            ]
        )
        // FR-16.3.1's scope, added after the other three: a rename here reinterprets every stored
        // settings row, since `RecordVocabulary.resolve` reads a spelling and not an ordinal.
        #expect(
            RecentRecordsScope.allCases.map(\.rawValue) == [
                "dashboardLifts", "everyExercise", "chosen",
            ]
        )
    }
}
