import DerivedValues
import DesignSystem
import DesignTokens
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

// A file of its own rather than more of `PastSessionView.swift`, which had reached SwiftLint's
// length ceiling — `PersonalRecordSourceLinks`' rule. Same screen, same surface.

/// One exercise as it was performed, in a session that is over.
///
/// **The live card's contents without its commands.** `SessionExerciseCard` carries `FR-1.2.2`'s
/// reorder, `FR-1.2.6`'s repeat and `FR-1.2.3`'s add — three things a past session does not offer —
/// and `FR-1.2.13`'s fold, which exists so a lifter mid-workout can get past what they have already
/// done. What is shared is the part that matters: ``SetRow`` and ``SetNumbering``, so a set reads
/// identically wherever it is drawn.
///
/// Taking the exercise and the unit rather than the state, so a reference can render it without a
/// repository behind it.
struct PastSessionExerciseCard: View {
    /// The exercise, its entry and its sets.
    let item: SessionExercise

    /// The locale this card resolves its exercise's name in (`FR-1.14.2`).
    @Environment(\.locale) private var locale

    /// The unit this card's loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// Whether this card's warmup group is open (`FR-1.2.14`).
    let areWarmupsExpanded: Bool

    /// Opens or closes it.
    let toggleWarmups: () -> Void

    /// Which of this card's set groups the user has opened (`FR-16.1.3`), keyed on the group.
    let expandedGroups: Set<UUID>

    /// Opens or closes one of them.
    let toggleGroup: (UUID) -> Void

    /// Opens `FR-1.2.7`'s editor over one of this card's sets.
    let edit: (SetEntry) -> Void

    /// The schemes one of this card's sets holds a record at (`FR-17.7.2`), or none.
    ///
    /// **The cache's truth, which is *holds the record now*** — see
    /// ``SessionRecordMarks/read(over:from:)``. A run since beaten carries no badge, which is what
    /// the requirement asks for and is also the only claim a screen about last month can honestly
    /// make: the table is rebuilt from the log and remembers no history of its own.
    var recordSchemes: (UUID) -> [RecordScheme] = { _ in [] }

    /// Whether the session this card belongs to has yet to end (`FR-16.4.1`).
    ///
    /// **Not always `false`, which is what a "past session" screen would suggest.** The screen is
    /// reached from the history list, and a session that was imported or abandoned is on that list
    /// while still open — its uncompleted sets are pending rather than missed.
    var isSessionOpen = false

    /// The exercise's name, then its sets.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                name
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                if item.sets.isEmpty {
                    // The set list's own copy, shared with the live card because it is one component
                    // drawn on two screens rather than two screens saying the same thing.
                    Text(LoggingStrings.setListEmpty)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textSecondary)
                } else {
                    warmupGroup
                    ForEach(workingGroups) { groupRow(for: $0) }
                }
            }
        }
    }

    /// `FR-1.2.14`'s warmups, folded by default: see ``PastSessionView/warmupExpansion``.
    @ViewBuilder private var warmupGroup: some View {
        if !warmups.isEmpty {
            WarmupSectionHeader(
                count: warmups.count, isExpanded: areWarmupsExpanded, toggle: toggleWarmups)
            if areWarmupsExpanded {
                ForEach(warmupGroups) { groupRow(for: $0) }
            }
        }
    }

    /// One group's line, with the two marking controls absent — see ``SetRow/mark``.
    ///
    /// - Parameter group: The run of identical sets, and their numbers.
    /// - Returns: The line.
    private func groupRow(for group: NumberedSetGroup) -> some View {
        SetGroupRow(
            group: group,
            unit: unit,
            isExpanded: expandedGroups.contains(group.id),
            toggle: { toggleGroup(group.id) },
            mark: nil,
            markCompleted: nil,
            edit: edit,
            recordSchemes: recordSchemes,
            // `FR-15.3.1`'s line, where a routine planned this set. A free workout plans nothing
            // and this map is empty for it, which costs the card no line at all — the state reads
            // the targets either way, because a workout started from a routine carries no program
            // stamp and is still drawn here.
            target: { targets[$0] },
            trainingMax: item.trainingMax,
            isSessionOpen: isSessionOpen
        )
    }

    /// What each of this card's sets was planned against, keyed on the set (`FR-15.3.1`).
    private var targets: [UUID: PlannedTargetGroup] { item.plannedTargets }

    /// This card's sets, each carrying its number within its own sequence (`FR-1.2.14`).
    private var numberedSets: [NumberedSet] { SetNumbering.numbered(item.sets) }

    /// The warmups among them, in the order they were logged.
    private var warmups: [NumberedSet] { numberedSets.filter(\.isWarmup) }

    /// The work proper, likewise.
    private var workingSets: [NumberedSet] { numberedSets.filter { !$0.isWarmup } }

    /// The work proper as `FR-16.1.1`'s groups — grouped after the partition, on the live card's
    /// rule.
    private var workingGroups: [NumberedSetGroup] { SetNumbering.grouped(workingSets) }

    /// The warmups likewise, inside their own fold.
    private var warmupGroups: [NumberedSetGroup] { SetNumbering.grouped(warmups) }

    /// The exercise's name, or a sentence in place of one — see ``SessionExercise/exercise``.
    private var name: Text {
        guard let exercise = item.exercise else {
            return Text(LoggingStrings.sessionExerciseMissing)
        }
        return Text(verbatim: exercise.displayName(for: locale))
    }
}
