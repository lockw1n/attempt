import ExerciseLibrary
import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import Routines
import SwiftUI
import Testing
import UIKit

@testable import Attempt

/// The walk `FR-18.1.3` and `FR-18.1.4` describe, through the app's own composition: a picker whose
/// search matched nothing, the **Create "‹typed›"** it now offers, and the saved exercise arriving
/// where the picker's closure puts it.
///
/// **Here rather than in `ExerciseLibrary`, because the join is the app target's** (`TR-1.3`). The
/// library screen takes a closure and knows nothing about a workout; the stores take an identifier
/// and know nothing about a catalogue. A package test can prove each half and only this bundle can
/// prove they meet — which is what `scripts/app-tests.sh` exists for, and why this task runs it by
/// hand.
///
/// **The search field is driven through its `UITextField`**, not through the accessibility tree:
/// activation is a double-tap and there is no typing in it. That is the one piece of this walk that
/// is not what a finger does — everything after it is.
///
/// **Serialized, for ``ScreenWiringTests``' reason**: the scene is shared and a second key window
/// mid-test changes what the first one's presentation does.
///
/// **What these walks do not cover is the exit**, and it is worth saying where it went instead.
/// `FR-18.1.4` also asks that the lifter comes back to the screen that opened the picker, which
/// means removing the picker's own route — and `AttemptTests` does not link `AppNavigation`
/// (`T-1.96`), so no fixture here can put a real shell above the screen. That decision therefore
/// lives in ``AppNavigation/NavigationState/pop(_:)``, a plain type with its own tests, which is
/// the same answer `T-1.96` reached for `ScreenWakePolicy`. Hosted bare, these screens take that
/// method's `false` and fall back to ``SwiftUI/EnvironmentValues/dismiss``.
@MainActor
@Suite("Creating from a picker's no-match (FR-18.1.3, FR-18.1.4)", .serialized)
struct ExerciseCreationFromPickerTests {
    /// The Train tab's picker: what is created lands in the workout in progress.
    ///
    /// **`DOD-18.2`'s count is this walk's, and it is two**: Create and Save, and nothing else
    /// after typing. ``HostedScreen/createFromNoMatch(named:storedIn:)`` activates exactly those
    /// two controls, so the budget of three is read off the walk rather than asserted beside it —
    /// a third tap here would be a third `activateOrRecord` call.
    @Test("The day's picker adds the exercise it just created to the workout")
    func theDayPickerAddsWhatItCreated() async throws {
        let app = try PickerFixture()
        let screen = HostedScreen(
            NavigationStack {
                ExerciseListView(
                    repository: app.repositories.exercises, workouts: app.repositories.workouts
                ) { exercise in
                    await app.stores.activeSession.addExercise(id: exercise.id)
                }
            }
        )
        defer { screen.dismantle() }
        try await app.seedTheCatalogue()
        try await app.startWorkout()

        let created = try await screen.createFromNoMatch(
            named: "Rear delt fly", storedIn: app.repositories.exercises)

        await app.stores.activeSession.loadExercises()
        #expect(
            app.stores.activeSession.exercises.contains(where: { $0.exercise?.id == created.id }),
            """
            saved, and the day did not get it: the picker's select was not called with the new row \
            (FR-18.1.4). On the day: \
            \(app.stores.activeSession.exercises.compactMap { $0.exercise?.name })
            """)
    }

    /// Edit week's picker: the same walk, one feature over, into the day that is open.
    @Test("Edit week's picker adds the exercise it just created to the open day")
    func theWeekPickerAddsWhatItCreated() async throws {
        let app = try PickerFixture()
        try await app.seedTheCatalogue()
        let dayID = try await app.openADayInEditWeek()
        let screen = HostedScreen(
            NavigationStack {
                ExerciseListView(
                    repository: app.repositories.exercises, workouts: app.repositories.workouts
                ) { exercise in
                    await app.stores.weekEditor.addExercise(id: exercise.id)
                }
            }
        )
        defer { screen.dismantle() }

        let created = try await screen.createFromNoMatch(
            named: "Rear delt fly", storedIn: app.repositories.exercises)

        // Read back through the store rather than off the draft: `WeekEditorDay`'s slots are
        // `internal` to `Routines`, and the claim worth making is the one the week is rebuilt from
        // anyway — the routine the open day names now prescribes the exercise (`FR-15.2.1`).
        let planned = try await app.plannedExerciseIDs()
        #expect(
            planned.contains(created.id),
            """
            saved, and the week's plan did not get it: the picker's select was not called with the \
            new row (FR-18.1.4). Day \(dayID) was open; the week prescribes \(planned.count) \
            exercises.
            """)
    }

    /// The browsing list's own door: nothing is selected, and what is left to be right is the list.
    ///
    /// **This is the test that says whether the list re-reads after the form above it pops**
    /// (`FR-1.1.3`). A push does not take this screen out of the hierarchy, so whether its `.task`
    /// runs a second time on the way back down is a property of SwiftUI rather than of anything
    /// here — and the answer decides whether `ExerciseListView` owes itself an explicit re-read.
    /// The search text is still what was typed, so the row created under it is the row the list
    /// must now be able to draw.
    @Test("The browsing list draws the exercise it just created, on the way back down")
    func theListShowsWhatItJustCreated() async throws {
        let app = try PickerFixture()
        let screen = HostedScreen(
            NavigationStack {
                ExerciseListView(
                    repository: app.repositories.exercises, workouts: app.repositories.workouts)
            }
        )
        defer { screen.dismantle() }
        try await app.seedTheCatalogue()

        _ = try await screen.createFromNoMatch(
            named: "Rear delt fly", storedIn: app.repositories.exercises)
        await screen.settle()

        let labels = screen.activatableLabels()
        #expect(
            labels.contains(where: { $0.contains("Rear delt fly") }),
            """
            saved, and the list came back without it (FR-1.1.3): the catalogue this screen holds is \
            the one it read before the form was pushed. What it publishes: \(labels)
            """)
    }

    /// The app's own stores and repositories, opened in memory.
    struct PickerFixture {
        /// The repositories `RootTabView` hands a screen.
        let repositories: AppDependencies.Repositories

        /// The stores a picker's closure writes into.
        let stores: AppDependencies.Stores

        /// Opens the in-memory store.
        init() throws {
            guard case .open(let repositories, let stores) = AppDependencies.preview.state else {
                throw FixtureFailure.storeDidNotOpen
            }
            self.repositories = repositories
            self.stores = stores
        }

        /// Starts a workout, so the day's picker has somewhere to put an exercise.
        func startWorkout() async throws {
            await stores.activeSession.start(on: .now)
            guard stores.activeSession.isActive else { throw FixtureFailure.noWorkout }
        }

        /// Puts one exercise in the catalogue.
        ///
        /// **Without it the list draws the *empty catalogue* state, not the no-match one** — the
        /// in-memory store opens unseeded, and that state offers its own create action, which is a
        /// different door with a different label.
        func seedTheCatalogue() async throws {
            let now = Date.now
            try await repositories.exercises.save(
                Exercise(
                    id: UUID(),
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    name: "Back Squat",
                    ukrainianName: nil,
                    movement: .squat,
                    parentExerciseID: nil,
                    equipment: .barbell,
                    laterality: .bilateral,
                    barType: .standard,
                    implementCount: 1,
                    isCustom: false,
                    isArchived: false,
                    notes: ""))
        }

        /// Reads the week and unfolds its first day — which is the day ``addExercise(id:)`` targets.
        ///
        /// - Returns: That day's identifier.
        func openADayInEditWeek() async throws -> UUID {
            await stores.weekEditor.load()
            // The store opens with no program at all, so the week is authored here the way the
            // screen authors one: a day, which is what `addExercise(id:)` needs a target in.
            await stores.weekEditor.addDay()
            guard let day = stores.weekEditor.days.first else { throw FixtureFailure.noWeek }
            stores.weekEditor.openDayID = day.id
            return day.id
        }

        /// Every exercise the week's routines prescribe, however many days there are.
        ///
        /// - Returns: The catalogue identifiers.
        /// - Throws: Whatever the store throws.
        func plannedExerciseIDs() async throws -> Set<UUID> {
            var found: Set<UUID> = []
            for routine in try await repositories.routines.routines(includingDeleted: false) {
                let slots = try await repositories.routines.exercises(
                    forRoutineID: routine.id, includingDeleted: false)
                found.formUnion(slots.map(\.exerciseID))
            }
            return found
        }

        /// What can be wrong before a screen is ever hosted.
        enum FixtureFailure: Error {
            /// The in-memory store did not open.
            case storeDidNotOpen

            /// `start(on:)` left no workout in progress.
            case noWorkout

            /// The week editor read no day to add an exercise to.
            case noWeek
        }
    }
}

extension HostedScreen {
    /// Searches for something the catalogue does not have, creates it, and saves it.
    ///
    /// Every step is the lifter's: type, **Create "‹typed›"**, **Save**. The assertions in between
    /// are what says *which* step failed — a missing Create is `FR-18.1.3` and a missing Save is a
    /// form that did not open on the pushed screen.
    ///
    /// - Parameters:
    ///   - name: What to type, which is also what gets created.
    ///   - catalogue: The store the form wrote into — the fixture's own, never a second
    ///     ``Attempt/AppDependencies/preview``, which would open a store this screen never saw.
    /// - Returns: The stored exercise, read back from the catalogue by name.
    /// - Throws: Whatever the walk could not do, or a copy fault.
    func createFromNoMatch(
        named name: String, storedIn catalogue: any ExerciseRepository
    ) async throws -> Exercise {
        await settle()
        try #require(
            !accessibilityElements().isEmpty, Comment(rawValue: HostedScreen.accessibilityRemedy))

        try type(name, intoTheSearchField: true)
        await settle()

        let create = try ExerciseLibraryCopy.createLabel(for: name)
        try activateOrRecord(label: create, step: "Create — FR-18.1.3's own action")
        await settle()

        let save = try ExerciseLibraryCopy.string(forKey: "exerciselibrary.form.save")
        try activateOrRecord(
            label: save,
            step: "Save — the form did not open, or opened without the typed name in it")
        await settle()

        return try await Self.storedExercise(named: name, in: catalogue)
    }

    /// Activates a label and turns anything but success into a named failure.
    ///
    /// - Parameters:
    ///   - label: The control's accessibility label.
    ///   - step: What this step is, for the message.
    /// - Throws: ``WalkFailure`` when the control is missing or inert.
    private func activateOrRecord(label: String, step: String) throws {
        switch activate(label: label) {
        case .activated:
            return
        case .notFound:
            throw WalkFailure.controlMissing(step: step, label: label, published: activatableLabels())
        case .refused:
            throw WalkFailure.controlInert(step: step, label: label)
        }
    }

    /// The catalogue row the walk created.
    ///
    /// - Parameters:
    ///   - name: The name it was saved under.
    ///   - catalogue: The store the screen wrote into.
    /// - Returns: The exercise.
    /// - Throws: ``WalkFailure/nothingWasSaved(name:)`` when the save did not land.
    private static func storedExercise(
        named name: String, in catalogue: any ExerciseRepository
    ) async throws -> Exercise {
        guard
            let created =
                try await catalogue
                .exercises(includingDeleted: false)
                .first(where: { $0.name == name })
        else {
            throw WalkFailure.nothingWasSaved(name: name)
        }
        return created
    }

    /// Types into the screen's first text field.
    ///
    /// **`.editingChanged` is what updates the binding**: SwiftUI's `TextField` is a `UITextField`
    /// underneath and watches that action, so setting `text` alone would change the pixels and
    /// leave the state holding nothing.
    ///
    /// - Parameters:
    ///   - text: What to type.
    ///   - intoTheSearchField: Unused marker, so the call site reads as what it does.
    /// - Throws: ``WalkFailure/noTextField`` when the screen published none.
    private func type(_ text: String, intoTheSearchField: Bool) throws {
        guard let root = controller.viewIfLoaded, let field = Self.firstTextField(in: root) else {
            throw WalkFailure.noTextField
        }
        field.becomeFirstResponder()
        field.text = text
        field.sendActions(for: .editingChanged)
    }

    /// The first `UITextField` under `view`, depth first.
    ///
    /// - Parameter view: Where to start.
    /// - Returns: The field, or `nil`.
    private static func firstTextField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for subview in view.subviews {
            if let field = firstTextField(in: subview) { return field }
        }
        return nil
    }

    /// What a walk could not do, said as the step it could not do it at.
    enum WalkFailure: Error, CustomStringConvertible {
        /// The screen published no text field to type into.
        case noTextField

        /// No activatable element carried that label.
        case controlMissing(step: String, label: String, published: [String])

        /// The element was there and declined to activate.
        case controlInert(step: String, label: String)

        /// The walk finished and the catalogue holds no row by that name.
        case nothingWasSaved(name: String)

        /// What went wrong, and where to look.
        var description: String {
            switch self {
            case .noTextField:
                "the screen published no UITextField — there is nothing to type a search into."
            case .controlMissing(let step, let label, let published):
                """
                \(step): no activatable element labelled "\(label)". \
                What the screen published: \(published)
                """
            case .controlInert(let step, let label):
                """
                \(step): the element labelled "\(label)" is in the tree and declined to activate — \
                it was drawn disabled or inert, it is not missing.
                """
            case .nothingWasSaved(let name):
                """
                the walk reached Save and the catalogue holds no exercise named "\(name)": \
                the form saved nothing.
                """
            }
        }
    }
}

/// The `ExerciseLibrary` module's own copy, read from the resource bundle the app ships.
///
/// `LoggingCopy`'s argument, one module over: the constants are `internal` to that module, and a
/// literal here would be a second home for a string whose home is the `.strings` file. The
/// key-level check is the same one and is there for the same reason — a lookup with no value
/// answers with the key, and the screen would draw the key too.
enum ExerciseLibraryCopy {
    /// One string from the module's bundle.
    ///
    /// - Parameter key: The key as `ExerciseLibraryStrings` spells it.
    /// - Returns: The English copy, which is never the key.
    /// - Throws: `LoggingCopy.CopyFailure` if the bundle or the key is missing.
    static func string(forKey key: String) throws -> String {
        guard
            let url = Bundle.main.url(
                forResource: "ExerciseLibrary_ExerciseLibrary", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        else {
            throw LoggingCopy.CopyFailure.bundleMissing
        }
        let copy = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard copy != key else { throw LoggingCopy.CopyFailure.keyMissing(key) }
        return copy
    }

    /// **Create "‹name›"** as the screen labels it (`FR-18.1.3`).
    ///
    /// - Parameter name: The typed name the label quotes.
    /// - Returns: The label.
    /// - Throws: `LoggingCopy.CopyFailure` if the bundle or the key is missing.
    static func createLabel(for name: String) throws -> String {
        let format = try string(forKey: "exerciselibrary.list.no-matches.create %@")
        return String(format: format, name)
    }
}
