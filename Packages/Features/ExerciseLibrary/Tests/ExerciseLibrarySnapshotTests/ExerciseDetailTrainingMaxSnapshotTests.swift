#if os(iOS)

    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import ExerciseLibrary

    // TR-1.12 for FR-15.1's training max section, on `ExerciseDetailSnapshotTests`' terms and
    // sharing its `DetailFixtures` — a suite of its own only because that file had reached
    // SwiftLint's length ceiling, which is `ExerciseDetailTrainingMaxSnapshotTests`' whole reason
    // for existing.

    @MainActor
    @Suite("Exercise detail training max snapshots")
    struct ExerciseDetailTrainingMaxSnapshotTests {
        @Test func trainingMaxWithHistory() throws {
            // The number in force with `FR-15.1.5`'s indicator under it, the command, and
            // `FR-15.1.4`'s history disclosed — three changes, the oldest of which replaced nothing
            // and therefore reads "Set to" rather than "0 kg → 160 kg". That row is the reference's
            // sharpest claim: a first entry drawn as a change from zero reports a number the lifter
            // never had.
            //
            // The absent state is not a second reference: it is `T-1.09`'s insufficient-data view
            // over one sentence, which `ExerciseDetail-estimate-refused` already pictures at both
            // sizes.
            try assertSnapshots(named: "ExerciseDetail-training-max") {
                TrainingMaxReading(
                    state: .ready(
                        DetailFixtures.trainingMaxes[0], history: DetailFixtures.trainingMaxes),
                    unit: .kilograms,
                    hasFailedWrite: false,
                    showsHistory: .constant(true),
                    retry: {},
                    change: {}
                )
                .environment(\.locale, DetailFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func trainingMaxNotYetInForce() throws {
            // The state a forward-dated change lands in: nothing is in force, and the changes that
            // say so are right there under the disclosure. What this gates is that the two read as
            // one section — an explanation of an absence, the command, and a history that
            // contradicts neither. Drawing the insufficient-data sentence over an empty section
            // here would be hiding a row the lifter had just written (`FR-15.1.4`).
            try assertSnapshots(named: "ExerciseDetail-training-max-not-yet") {
                TrainingMaxReading(
                    state: .none(history: DetailFixtures.futureTrainingMaxes),
                    unit: .kilograms,
                    hasFailedWrite: false,
                    showsHistory: .constant(true),
                    retry: {},
                    change: {}
                )
                .environment(\.locale, DetailFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func trainingMaxEditor() throws {
            // `FR-16.7.2`'s three fields, which is the whole of what the sheet asks for: the
            // number, the day it takes effect, and the note.
            //
            // **All three controls rasterise as the unsupported-view placeholder** — two
            // `TextField`s and a `DatePicker`, every one of them UIKit-backed. That is the
            // harness's own limit, the same one the estimate's editor reference was a picture of.
            // What this gates is the three headings, the labels beside the controls, the unit and
            // the hint, and whether they survive `accessibility3`.
            try assertSnapshots(named: "ExerciseDetail-training-max-editor") {
                TrainingMaxEditorContent(
                    draft: .constant(DetailFixtures.trainingMaxDraft), unit: .kilograms
                )
                .environment(\.locale, DetailFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }
    }

#endif
