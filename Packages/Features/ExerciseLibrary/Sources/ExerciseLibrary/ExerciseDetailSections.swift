import DerivedValues
import DesignSystem
import Foundation
import RepositoryInterface
import SwiftUI

/// The screen's sections, in the order a lifter reads them (`FR-16.6.2`).
///
/// A type of its own rather than a method on the screen, so `TR-1.12` has something to render: the
/// screen's own body is a `ScrollView`, and the harness draws a placeholder for anything
/// UIKit-backed.
///
/// **The numbers come first.** The training max, the estimate, the records and the history are what
/// a screen is opened to check; the movement, the bar and the sides are static and already known to
/// whoever owns the exercise. The training max keeps the estimate directly beneath it — the coach's
/// number and the observed one are two claims about the same lift, and reading them in that order is
/// what stops either being taken for the other (`FR-15.1.5`).
///
/// **`FR-1.1.5`'s archive control is last, below all of them.** It is the one command here that
/// changes what the rest of the app shows, and the foot of a screen is where a command like that is
/// reached deliberately rather than in passing. Its badge is not: that goes at the head, above every
/// section, because an archived exercise is still reachable from logged history and the badge is the
/// screen's only answer to why it is absent from the list.
struct ExerciseDetailSections: View {
    /// The exercise and its relationships, already read.
    let detail: ExerciseDetail

    /// The notes editor's binding, and the archive command's.
    let state: ExerciseDetailState

    /// Which exercise the four reading sections are about.
    let exerciseID: UUID

    /// Where the history section's sets come from.
    let workouts: any WorkoutRepository

    /// Where the display unit comes from (`G-3.1`).
    let settings: any SettingsRepository

    /// The app's one recompute actor (`TR-1.6`).
    let records: PersonalRecordRecomputer

    /// Where `FR-15.1`'s training max and its history are stored.
    let trainingMaxes: any TrainingMaxRepository

    /// The badge, then the four derived sections, then the record's own fields, then the archive.
    ///
    /// Each derived section reads for itself, with its own store, its own `.task` and its own
    /// states — so a value that cannot be computed costs the reader that section and never
    /// `FR-1.1.6`'s movement, equipment and notes.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl.points) {
            if detail.exercise.isArchived {
                ExerciseArchivedBadge()
            }
            TrainingMaxSection(
                exerciseID: exerciseID,
                trainingMaxes: trainingMaxes,
                settings: settings,
                records: records
            )
            ExerciseEstimateSection(exerciseID: exerciseID, records: records, settings: settings)
            // The set count is handed down, because it is what separates the two "nothing to show"
            // sentences and this screen is the only place it has already been read.
            //
            // THE ESTIMATE IS NOT GIVEN IT, and that is deliberate. A 12-rep set, assisted work and
            // a set that targets ten and fails at eight each produce no estimate BY DESIGN, so a
            // user can have logged sets and still correctly have no e1RM — a count cannot tell those
            // apart from an exercise nothing has been logged against. The estimate's own section
            // reads the reason from the pipeline instead; see `ExerciseEstimateScreenState`.
            ExerciseRecordsSection(
                exerciseID: exerciseID,
                hasLoggedSets: detail.hasLoggedSets,
                records: records,
                settings: settings
            )
            ExerciseHistorySection(exerciseID: exerciseID, workouts: workouts, settings: settings)
            ExerciseFactsSection(exercise: detail.exercise)
            ExerciseNotesSection(state: state)
            if detail.hasRelationships {
                ExerciseVariationsSection(parent: detail.parent, variations: detail.variations)
            }
            ExerciseArchiveSection(
                isArchived: detail.exercise.isArchived,
                hasFailed: state.archiveFailure != nil
            ) {
                Task { await state.setArchived(!detail.exercise.isArchived) }
            }
        }
    }
}

/// The mark an archived exercise carries (`FR-1.1.5`).
///
/// **At the head of the screen rather than beside the title**, because the title is the navigation
/// bar's — and rather than inside the facts, because the facts sit below the numbers and a reason
/// the exercise is missing from the list is no use four sections down.
struct ExerciseArchivedBadge: View {
    /// One word, on a raised chip.
    var body: some View {
        Text(ExerciseLibraryStrings.detailArchivedBadge)
            .font(Typography.metricLabel.font)
            .foregroundStyle(ColorToken.textSecondary)
            .padding(.horizontal, Spacing.sm.points)
            .padding(.vertical, Spacing.xs.points)
            .background(
                ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )
    }
}
