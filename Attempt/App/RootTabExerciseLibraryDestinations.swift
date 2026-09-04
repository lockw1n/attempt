import AppNavigation
import DesignSystem
import ExerciseLibrary
import Logging
import RepositoryInterface
import Routines
import SwiftUI

// The exercise library's own destinations, in a file of their own.
//
// SPLIT FOR SIZE RATHER THAN FOR STRUCTURE, on `RootTabSettingsDestinations.swift`'s argument and
// along the line `exerciseLibraryDestination(_:)` was already drawn along in T-1.50: one area's
// share of the destination table. `T-16.06` added a seventh route here — `FR-16.2.4`'s record table
// — and that was what took `RootTabView.swift` past the file and type-body limits the lint rules
// hold every other file to.
//
// INTERNAL RATHER THAN PRIVATE, which is what the split costs and why only the members the shell
// actually calls are reachable: `exerciseLibraryDestination(_:)` for the switch, and the two
// pickers' roots, which the routines area's own destination reaches for.
extension RootTabView {
    /// What a pushed exercise-library route shows.
    ///
    /// Split out of ``destination(for:)`` for ``settingsDestination(_:)``'s reason: that switch is
    /// one case per screen in the app, and this area's cases are what took it past the complexity
    /// the lint rules allow — six of them when `T-15.02` split this method out, seven now that
    /// `FR-16.2.4`'s table has a route of its own.
    @ViewBuilder
    func exerciseLibraryDestination(_ route: ExerciseLibraryRoute) -> some View {
        switch route {
        case .exerciseList:
            // No title here: a pushed screen names itself, and this one does (`FR-1.1.1`). The tab
            // roots are the case where the app target owns the name — see ``AppTab/title``.
            exerciseListRoot
        case .exerciseDetail(let exerciseID):
            exerciseDetailRoot(exerciseID)
        case .exerciseRecords(let exerciseID):
            exerciseRecordsRoot(exerciseID)
        case .exerciseCreate:
            exerciseFormRoot(.create)
        case .exerciseEdit(let exerciseID):
            exerciseFormRoot(.edit(exerciseID: exerciseID))
        case .exercisePicker:
            exercisePickerRoot
        case .routineExercisePicker:
            routineExercisePickerRoot
        }
    }

    /// The exercise library's list, or the reason it cannot be shown.
    ///
    /// The same shape as ``settingsRoot``: a screen that reads a store cannot be built when the
    /// store did not open, and the diagnostic is the app's rather than the screen's.
    @ViewBuilder
    var exerciseListRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            ExerciseListView(repository: repositories.exercises, workouts: repositories.workouts)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// One exercise's detail, or the reason it cannot be shown.
    ///
    /// The screen is handed the identifier the route carried, not a record: resolving it is the
    /// screen's own first read (`G-1.4`).
    @ViewBuilder
    func exerciseDetailRoot(_ exerciseID: UUID) -> some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            ExerciseDetailView(
                exerciseID: exerciseID,
                repository: repositories.exercises,
                workouts: repositories.workouts,
                settings: repositories.settings,
                records: stores.records
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The create/edit form, or the reason it cannot be shown.
    ///
    /// - Parameter mode: Which of `FR-1.1.3` and `FR-1.1.4` the route asked for.
    @ViewBuilder
    func exerciseFormRoot(_ mode: ExerciseFormMode) -> some View {
        switch dependencies.state {
        case .open(let repositories, _):
            ExerciseFormView(mode: mode, repository: repositories.exercises)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The catalogue as `FR-1.2.2`'s chooser, or the reason it cannot be shown.
    ///
    /// **This is the join between the two feature modules that share the Train tab**, and it is here
    /// because nowhere else may make it: `Logging` and `ExerciseLibrary` do not depend on each other
    /// (`TR-1.3`), so the screen that chooses an exercise and the store that receives one are
    /// composed by the target that already owns both. The library screen takes a closure and knows
    /// nothing about workouts; the store takes an identifier and knows nothing about catalogues.
    @ViewBuilder
    var exercisePickerRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            ExerciseListView(
                repository: repositories.exercises, workouts: repositories.workouts
            ) { exercise in
                await stores.activeSession.addExercise(id: exercise.id)
            }
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The catalogue as the routine editor's chooser (`FR-15.2.1`), or the reason it cannot be
    /// shown.
    ///
    /// **The same join as ``exercisePickerRoot``, one feature over**: `Routines` and
    /// `ExerciseLibrary` do not depend on each other (`TR-1.3`), so the screen that chooses an
    /// exercise and the store that receives one are composed here. The two pickers are two route
    /// cases rather than one with a mode because *this* closure is the whole difference between
    /// them, and it is chosen from the route alone.
    @ViewBuilder
    var routineExercisePickerRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            ExerciseListView(
                repository: repositories.exercises, workouts: repositories.workouts
            ) { exercise in
                await stores.routineEditor.addExercise(id: exercise.id)
            }
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// `FR-16.2.4`'s whole record table for one exercise, or the reason it cannot be shown.
    ///
    /// Two dependencies, on ``recentRecordsRoot``'s terms with one fewer: the cells are the cached
    /// records and the unit is the settings row's; the exercise's own name is the navigation bar's,
    /// which the detail screen behind this one already put there.
    @ViewBuilder
    func exerciseRecordsRoot(_ exerciseID: UUID) -> some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            ExerciseRecordsTableView(
                exerciseID: exerciseID,
                records: stores.records,
                settings: repositories.settings
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }
}
