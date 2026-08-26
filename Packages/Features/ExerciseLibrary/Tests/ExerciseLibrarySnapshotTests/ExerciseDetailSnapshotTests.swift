#if os(iOS)

    import DerivedValues
    import DesignSystem
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import ExerciseLibrary

    // TR-1.12 for the detail screen, in the same four configurations as the list's references and on
    // the same terms — see `ExerciseListSnapshotTests` for why the pieces are rendered rather than the
    // screen, why a row's text is dimmer here than in the app, and why the copy is the real copy.
    //
    // FR-1.5.2's history is covered as a group rather than as a section, on the same terms: the
    // section's body is a `.task` that reads a store, and what a group of rows looks like is the
    // thing TR-1.12 is a gate over.
    //
    // THE HISTORY REFERENCE PINS ITS LOCALE AND ITS TIME ZONE, and it is the only one here that
    // renders anything either can reach. The harness pins neither, so an unpinned reference records
    // whatever REGION the recording Mac is set to — not its language. That is the failure this
    // suite shipped with: recorded under `en_US@rg=uazzzz`, whose decimal separator is a comma, and
    // compared on a runner under plain `en_US`, whose separator is a full stop. Four separators and
    // a date is 201 pixels, which reads as a rendering regression and is a machine difference.
    // `SessionListSnapshotTests` and `SessionSnapshotFixtures` had already met the same trap.
    //
    // THE NOTES SECTION HAS NO REFERENCE, and that is the harness's limit rather than an omission: it
    // is a `TextField`, `ImageRenderer` draws its unsupported-view placeholder for anything
    // UIKit-backed, and a reference over a grey rectangle would be a gate over nothing. What the notes
    // editor does is covered by `ExerciseDetailStateTests`; what it looks like is the simulator run's
    // (`docs/phase-1/tasks.md` §2).

    @MainActor
    @Suite("Exercise detail snapshots")
    struct ExerciseDetailSnapshotTests {
        @Test func facts() throws {
            try assertSnapshots(named: "ExerciseDetail-facts") {
                ExerciseFactsSection(exercise: DetailFixtures.frontSquat)
            }
        }

        @Test func archivedFacts() throws {
            try assertSnapshots(named: "ExerciseDetail-facts-archived") {
                ExerciseFactsSection(exercise: DetailFixtures.retired)
            }
        }

        @Test func variations() throws {
            try assertSnapshots(named: "ExerciseDetail-variations") {
                ExerciseVariationsSection(
                    parent: DetailFixtures.backSquat,
                    variations: [DetailFixtures.frontSquat, DetailFixtures.pauseSquat]
                )
            }
        }

        @Test func history() throws {
            // One picture with every row variant in it: a working set with a rating, one without,
            // a warmup, and a failed set. Four references over four rows rather than four suites —
            // what each of the four does to the row is a font, a colour and a word, and they are
            // only comparable side by side.
            try assertSnapshots(named: "ExerciseDetail-history") {
                ExerciseHistoryGroupView(group: DetailFixtures.trainingDay, unit: .kilograms)
                    .environment(\.locale, DetailFixtures.locale)
                    .environment(\.timeZone, .gmt)
            }
        }

        @Test func personalRecords() throws {
            // FR-1.6.2's list, at the shape the section draws when the disclosure is closed and again
            // when it is open. Rendered as rows rather than as `ExerciseRecordsSection`, on the
            // history section's terms: that view's body is a `.task` over a recompute actor.
            //
            // THE ROWS ARE THE UNLINKED FORM, which is what a record whose source set could not be
            // located draws — and it is also what the linked one looks like, since the link is a
            // `NavigationLink` with the plain button style over exactly this content. What cannot be
            // pictured is the NavigationStack it needs to be a control at all: the stack is
            // UIKit-backed, so a reference taken through one is the renderer's placeholder. That the
            // link navigates is `ExerciseRecordsSectionTests`', and that it looks right is the
            // simulator run's.
            let list = ExerciseRecordList(DetailFixtures.repMaxes)
            try assertSnapshots(named: "ExerciseDetail-records") {
                GroupedSection(Text(ExerciseLibraryStrings.recordsSection)) {
                    ForEach(list.prominent, id: \.reps) { repMax in
                        ExerciseRecordRow(repMax: repMax, unit: .kilograms, sessionID: nil)
                    }
                    RecordDisclosureHeader(isExpanded: false) {}
                }
                .environment(\.locale, DetailFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func personalRecordsDisclosed() throws {
            // The same section with FR-1.6.2's disclosure open — the 6–10RM under the control, and
            // the chevron turned. Two references rather than one, because "behind an explicit
            // disclosure control" is a claim about what is NOT on screen in the first of them.
            let list = ExerciseRecordList(DetailFixtures.repMaxes)
            try assertSnapshots(named: "ExerciseDetail-records-disclosed") {
                GroupedSection(Text(ExerciseLibraryStrings.recordsSection)) {
                    ForEach(list.prominent, id: \.reps) { repMax in
                        ExerciseRecordRow(repMax: repMax, unit: .kilograms, sessionID: nil)
                    }
                    RecordDisclosureHeader(isExpanded: true) {}
                    ForEach(list.disclosed, id: \.reps) { repMax in
                        ExerciseRecordRow(repMax: repMax, unit: .kilograms, sessionID: nil)
                    }
                }
                .environment(\.locale, DetailFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func derivedValueWithNothingToShow() throws {
            try assertSnapshots(named: "ExerciseDetail-derived") {
                DerivedValueSection(
                    title: ExerciseLibraryStrings.e1rmSection,
                    nothingYet: ExerciseLibraryStrings.e1rmNone
                )
            }
        }

        @Test func archiveControl() throws {
            try assertSnapshots(named: "ExerciseDetail-archive") {
                ExerciseArchiveSection(isArchived: false, hasFailed: false) {}
            }
        }

        @Test func unarchiveControl() throws {
            // The archived direction *and* the failed write in one reference: they are the two
            // things this section renders that the live one does not, and a screen showing both is
            // the state a retry is offered from.
            try assertSnapshots(named: "ExerciseDetail-unarchive") {
                ExerciseArchiveSection(isArchived: true, hasFailed: true) {}
            }
        }

        @Test func exerciseNotFound() throws {
            try assertSnapshots(named: "ExerciseDetail-missing") {
                ErrorStateView(
                    headline: Text(ExerciseLibraryStrings.detailMissingHeadline),
                    message: Text(ExerciseLibraryStrings.detailMissingMessage)
                )
            }
        }
    }

    /// The exercises these references render: a parent, two variations, and an archived one.
    ///
    /// The variation carries a non-default bar and laterality so the reference shows the vocabulary
    /// mapping doing something rather than five rows of the schema's defaults.
    enum DetailFixtures {
        /// The locale the history reference renders its date, loads and ratings for.
        ///
        /// Pinned because a Mac's region is not its language: `en_US@rg=uazzzz` is a US English
        /// machine that writes `102,5`, and it is what recorded this suite's first history images.
        static let locale = Locale(identifier: "en_US")

        static let backSquat = Fixtures.exercise(id: 1, name: "Back Squat", movement: .squat)

        static let frontSquat = Fixtures.exercise(
            id: 2,
            name: "Front Squat",
            movement: .squat,
            isCustom: true,
            laterality: .unilateral,
            barType: .safetySquat
        )

        static let pauseSquat = Fixtures.exercise(id: 3, name: "Pause Squat", movement: .squat)

        static let retired = Fixtures.exercise(
            id: 4,
            name: "Retired Machine Press",
            movement: .bench,
            equipment: .machine,
            isArchived: true,
            barType: .noBar
        )

        /// One training day, carrying every distinction a history row draws (`FR-1.5.2`).
        ///
        /// The date is fixed rather than relative to now, so a reference committed today still
        /// matches next year. THE PAGE CONTROL HAS NO REFERENCE, and that is the same limit the
        /// notes section runs into one layer up: it lives inside `ExerciseHistorySection`, whose
        /// body is a `.task` that reads a store. What it does is `ExerciseHistoryStateTests`', and
        /// what it looks like is the simulator run's.
        static let trainingDay = ExerciseSessionHistory(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sets: [
                loggedSet(order: 0, kilos: 60, reps: 5, isWarmup: true),
                loggedSet(order: 1, kilos: 102.5, reps: 5, rpe: 8),
                loggedSet(order: 2, kilos: 102.5, reps: 5),
                loggedSet(order: 3, kilos: 102.5, reps: 3, rpe: 9.5, isCompleted: false),
            ]
        )

        /// One exercise's records, one at every N the two references have to picture.
        ///
        /// **Five N's, not ten**, and the gaps are the point: an N no set reached is absent rather
        /// than drawn at zero, so the prominent half has three rows and the disclosed half two.
        static let repMaxes: [DatedRepMax] = [
            repMax(reps: 1, kilos: 140, daysAgo: 42),
            repMax(reps: 3, kilos: 125, daysAgo: 14),
            repMax(reps: 5, kilos: 110, daysAgo: 7),
            repMax(reps: 8, kilos: 95, daysAgo: 28),
            repMax(reps: 10, kilos: 85, daysAgo: 63),
        ]

        /// One record, spelled out once so a field nothing in the picture turns on is not repeated.
        ///
        /// The source set is a fixed identifier rather than a fresh `UUID` for the reason every other
        /// fixture here has one: nothing in these renderings may depend on a value that changes per
        /// run, and a row keyed on a fresh one could not be looked up in a links map either.
        private static func repMax(reps: Int, kilos: Double, daysAgo: Int) -> DatedRepMax {
            DatedRepMax(
                reps: reps,
                record: DatedRecord(
                    weight: Weight(grams: Int(kilos * 1000)),
                    sourceSetID: UUID(
                        uuidString: "0F5A1E24-9B7D-4C31-8E62-0000000000\(String(format: "%02d", reps))"
                    ) ?? UUID(),
                    achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
                        .addingTimeInterval(-Double(daysAgo) * 86_400)
                )
            )
        }

        /// One set, spelled out once so a field nothing in the picture turns on is not repeated.
        private static func loggedSet(
            order: Int,
            kilos: Double,
            reps: Int,
            rpe: Double? = nil,
            isWarmup: Bool = false,
            isCompleted: Bool = true
        ) -> SetEntry {
            let stamp = Date(timeIntervalSince1970: 1_700_000_000)
            return SetEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                entryID: UUID(),
                order: order,
                weight: Weight(grams: Int(kilos * 1000)),
                reps: reps,
                rpe: rpe,
                rir: nil,
                isWarmup: isWarmup,
                isCompleted: isCompleted,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: nil
            )
        }
    }

#endif
