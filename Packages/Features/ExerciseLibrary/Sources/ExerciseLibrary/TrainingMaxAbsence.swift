import Foundation

/// Which of the two things "no training max" can mean, and the copy each one gets (`FR-17.5.1`).
///
/// **A type rather than a ternary in the view**, because the two sentences are the claim this state
/// makes: an exercise that has never had a coach's number and one whose every change is dated ahead
/// of today are different statements, and until this existed the difference lived in a `?:` inside a
/// `switch` that nothing could assert against.
///
/// **Neither sentence says *not enough data*.** A training max is entered, never computed, so there
/// is no data for there to be too little of — which is the whole of review finding 07's copy half.
enum TrainingMaxAbsence: Equatable, CaseIterable {
    /// Nothing has ever been entered for this exercise. The common case: 132 of them at a fresh
    /// install, and the reason this state is a line rather than a section.
    case never

    /// Changes exist and every one of them takes effect on a later date (`FR-15.1.4`).
    case notInForceYet

    /// What the line says.
    var line: LocalizedStringResource {
        switch self {
        case .never: ExerciseLibraryStrings.trainingMaxNoneLine
        case .notInForceYet: ExerciseLibraryStrings.trainingMaxNotYetLine
        }
    }

    /// The sentence the line was shortened from, which is what VoiceOver reads (`G-4.2`).
    ///
    /// **Both lines are short and both sentences survive**, on the dashboard's empty tile's rule
    /// (`FR-16.5.2`): the line is short so that it can be a line, and a reader who cannot see the
    /// layout is owed the whole of it. ``notInForceYet``'s is the one that had to be shortened
    /// rather than the one that wanted to be — its sentence runs to five lines at the default type
    /// size, which is a paragraph with a button floating beside it.
    var hint: LocalizedStringResource? {
        switch self {
        case .never: ExerciseLibraryStrings.trainingMaxNone
        case .notInForceYet: ExerciseLibraryStrings.trainingMaxNotYet
        }
    }
}
