#if os(iOS)

    import DerivedValues
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import ExerciseLibrary

    // TR-1.12 over `FR-16.6.2`'s order, which is the one claim this screen's other references cannot
    // carry: they picture a section each, and a section cannot be out of order on its own. A suite of
    // its own because the detail file is at SwiftLint's length ceiling, which is the reason the
    // training max's references have one too.
    //
    // EVERY READING SECTION IS ITS HEADING OVER A PLACEHOLDER, and that is the reference rather
    // than a limit of it. `ImageRenderer` rasterises once and never runs a `.task`, so the four
    // derived sections are in their loading state, whose `ProgressView` is UIKit-backed and draws
    // as the unsupported-view mark — as does the notes field, for the reason
    // `ExerciseDetailSnapshotTests` gives. What is left is nine headings in one column, which is
    // exactly the claim under test. What each section looks like once it has read is its own
    // reference's.
    //
    // TWO REFERENCES, BECAUSE THE ORDER IS NOT THE ONLY CLAIM HERE. The first fixture is archived and
    // carries a variation, so one picture holds every section this screen can draw: `FR-1.1.5`'s badge
    // at the head, the four derived sections, the record's own fields, the notes, `FR-1.1.7`'s
    // relationships, and the archive control at the foot. The second has neither, which is what gates
    // the two `if`s — a picture in which every conditional is true cannot tell an `if` from an
    // unconditional draw.

    @MainActor
    @Suite("Exercise detail section order")
    struct ExerciseDetailOrderSnapshotTests {
        @Test func sectionOrder() throws {
            try assertSnapshots(named: "ExerciseDetail-section-order") {
                ExerciseDetailSections(
                    detail: ExerciseDetail(
                        exercise: DetailFixtures.retired,
                        parent: DetailFixtures.backSquat,
                        variations: [DetailFixtures.pauseSquat],
                        hasLoggedSets: true
                    ),
                    state: ExerciseDetailState(
                        exerciseID: DetailFixtures.retired.id,
                        repository: SilentStore(),
                        workouts: SilentStore()
                    ),
                    exerciseID: DetailFixtures.retired.id,
                    workouts: SilentStore(),
                    settings: SilentStore(),
                    records: PersonalRecordRecomputer(workouts: SilentStore(), cache: SilentStore()),
                    trainingMaxes: SilentStore()
                )
                .environment(\.locale, DetailFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func sectionOrderWithoutBadgeOrVariations() throws {
            // The negative half, and it is the reference the reorder made necessary rather than a
            // second picture of the same thing. Both of this screen's conditionals live in
            // `ExerciseDetailSections` now, and the reference above has both of them TRUE — so an
            // `if` deleted from either would still match it. Until T-16.10 the badge's own pair was
            // `ExerciseDetail-facts` against `ExerciseDetail-facts-archived`; moving the badge out
            // of `ExerciseFactsSection` left the true half here and the false half nowhere.
            //
            // An unarchived exercise with no parent and no variations: no badge at the head, no
            // `FR-1.1.7` section between the notes and the archive control, and the archive control
            // reading **Archive** rather than **Unarchive**.
            try assertSnapshots(named: "ExerciseDetail-section-order-plain") {
                ExerciseDetailSections(
                    detail: ExerciseDetail(
                        exercise: DetailFixtures.frontSquat,
                        parent: nil,
                        variations: [],
                        hasLoggedSets: false
                    ),
                    state: ExerciseDetailState(
                        exerciseID: DetailFixtures.frontSquat.id,
                        repository: SilentStore(),
                        workouts: SilentStore()
                    ),
                    exerciseID: DetailFixtures.frontSquat.id,
                    workouts: SilentStore(),
                    settings: SilentStore(),
                    records: PersonalRecordRecomputer(workouts: SilentStore(), cache: SilentStore()),
                    trainingMaxes: SilentStore()
                )
                .environment(\.locale, DetailFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }
    }

    /// Every store the sections take, answering nothing.
    ///
    /// One type rather than five, because none of them is asked anything: the sections read in a
    /// `.task`, and the harness never runs one. Empty where a type has one, and a refusal where a
    /// value would otherwise have to be invented — the settings row being the only such answer.
    private struct SilentStore: ExerciseRepository {
        func exercises(includingDeleted: Bool) async throws -> [Exercise] { [] }
        func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? { nil }
        func save(_ exercise: Exercise) async throws {}
    }

    extension SilentStore: WorkoutRepository {
        func sessions(
            forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
        ) async throws -> [WorkoutSession] {
            []
        }
        func sessions(
            in range: ClosedRange<Date>, includingDeleted: Bool
        ) async throws -> [WorkoutSession] { [] }
        func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { nil }
        func save(_ session: WorkoutSession) async throws {}
        func deleteSession(id: UUID) async throws {}
        func entries(
            forSessionID sessionID: UUID, includingDeleted: Bool
        ) async throws -> [ExerciseEntry] { [] }
        func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { nil }
        func save(_ entry: ExerciseEntry) async throws {}
        func deleteExerciseEntry(id: UUID) async throws {}
        func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] { [] }
        func save(_ set: SetEntry) async throws {}
        func deleteSet(id: UUID) async throws {}
        func sets(
            forExerciseID exerciseID: UUID, includingDeleted: Bool
        ) async throws -> [SetEntry] { [] }
    }

    extension SilentStore: SettingsRepository {
        func settings() async throws -> UserSettings {
            throw RepositoryError.recordNotFound(id: UUID())
        }
        func save(_ settings: UserSettings) async throws {}
        func restorePreferences(from backup: UserSettings) async throws {}
    }

    extension SilentStore: TrainingMaxRepository {
        func configuration(
            forExerciseID exerciseID: UUID, on date: Date
        ) async throws -> TrainingMaxEntry? { nil }
        func configurationHistory(
            forExerciseID exerciseID: UUID, includingDeleted: Bool
        ) async throws -> [TrainingMaxEntry] { [] }
        func saveConfiguration(_ entry: TrainingMaxEntry) async throws {}
        func trainingMax(
            forExerciseID exerciseID: UUID, on date: Date
        ) async throws -> TrainingMaxHistoryEntry? { nil }
        func history(
            forExerciseID exerciseID: UUID, includingDeleted: Bool
        ) async throws -> [TrainingMaxHistoryEntry] { [] }
        func save(_ entry: TrainingMaxHistoryEntry) async throws {}
        func deleteEntry(id: UUID) async throws {}
    }

    extension SilentStore: PersonalRecordCacheRepository {
        func personalRecords(
            forExerciseID exerciseID: UUID, includingDeleted: Bool
        ) async throws -> [PersonalRecordCache] { [] }
        func personalRecords(includingDeleted: Bool) async throws -> [PersonalRecordCache] { [] }
        func replacePersonalRecords(
            forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
        ) async throws {}
    }

#endif
