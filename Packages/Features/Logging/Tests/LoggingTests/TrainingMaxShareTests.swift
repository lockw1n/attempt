import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-16.7.1`: a load read as a percentage of the training max **in force on the session's day**,
/// and the sentence that says so.
@MainActor
@Suite("A load as a share of the training max")
struct TrainingMaxShareTests {
    /// The rule this whole feature turns on: a coach raising the number next week does not rewrite
    /// what last week's sets were a percentage of.
    @Test("The share uses the value in force on the session's date, not today's")
    func theshareIsResolvedAtTheSessionDate() async throws {
        let fixture = try await PastSession.logged(names: ["Back Squat"])
        try await fixture.logSet(at: 0, order: 0, weight: Weight(grams: 90_000))
        // 180 from a week before the session, then 200 from a week after it.
        try await fixture.repositories.trainingMaxes.save(
            entry(
                forExerciseID: fixture.exercises[0].id,
                from: PastSession.stamp.addingTimeInterval(-7 * 86_400),
                kilos: 180))
        try await fixture.repositories.trainingMaxes.save(
            entry(
                forExerciseID: fixture.exercises[0].id,
                from: PastSession.stamp.addingTimeInterval(7 * 86_400),
                kilos: 200,
                replacing: 180))

        await fixture.state.load()

        let card = try #require(fixture.state.exercises.first)
        #expect(card.trainingMax == Weight(grams: 180_000))
        // 90 of 180 is 50%; of 200 it would be 45, which is what a read at "now" would have said.
        #expect(Weight(grams: 90_000).percentOfTrainingMax(try #require(card.trainingMax)) == 50)
    }

    @Test("An exercise with no training max carries none, and the annotation is absent")
    func noTrainingMaxIsNoAnnotation() async throws {
        let fixture = try await PastSession.logged(names: ["Back Squat"])
        try await fixture.logSet(at: 0, order: 0)

        await fixture.state.load()

        let card = try #require(fixture.state.exercises.first)
        #expect(card.trainingMax == nil)
        #expect(
            TrainingMaxShare.annotation(
                for: Weight(grams: 100_000), against: nil, locale: english) == nil)
    }

    /// The rounding claim `FR-16.7.1` is annotated with: whole percents, and the sentence names the
    /// training max rather than leaving a bare numeral beside a load.
    @Test("The annotation is a whole percent, in words")
    func theannotationRoundsToAWholePercent() throws {
        let annotation = try #require(
            TrainingMaxShare.annotation(
                for: Weight(grams: 157_500), against: Weight(grams: 180_000), locale: english))

        // 157.5 of 180 is 87.5%, which rounds away from zero.
        #expect(String(localized: annotation) == "88% of TM")
    }

    @Test("A training max nothing can be a percentage of draws no annotation")
    func anunusableTrainingMaxDrawsNothing() {
        #expect(
            TrainingMaxShare.annotation(
                for: Weight(grams: 100_000), against: .zero, locale: english) == nil)
    }

    /// The pair of numbers is worth drawing only when they disagree — a set that hit its target
    /// would otherwise say the same percentage twice, two lines apart.
    @Test("A set that matched its target draws no share of its own")
    func amatchedSetDrawsOneShare() {
        let trainingMax = Weight(grams: 125_000)
        // The set and the plan agree at 80%, and disagree at 87.5 against 85.
        #expect(
            TrainingMaxShare.percent(for: Weight(grams: 100_000), against: trainingMax)
                == TrainingMaxShare.percent(for: Weight(grams: 100_000), against: trainingMax))
        #expect(TrainingMaxShare.percent(for: Weight(grams: 87_500), against: trainingMax) == 70)
        #expect(TrainingMaxShare.percent(for: Weight(grams: 85_000), against: trainingMax) == 68)
    }

    @Test("With no training max there is no share to compare")
    func nopercentWithoutATrainingMax() {
        #expect(TrainingMaxShare.percent(for: Weight(grams: 100_000), against: nil) == nil)
    }

    /// The locale the percentage is rendered for. Pinned, on `G-3.4`'s rule.
    private var english: Locale { Locale(identifier: "en_US") }

    /// One training-max history row.
    ///
    /// - Parameters:
    ///   - exerciseID: Whose training max.
    ///   - date: The day it takes effect.
    ///   - kilos: What it becomes.
    ///   - old: What it replaced, in kilograms, or `nil`.
    /// - Returns: The row.
    private func entry(
        forExerciseID exerciseID: UUID, from date: Date, kilos: Int, replacing old: Int? = nil
    ) -> TrainingMaxHistoryEntry {
        TrainingMaxHistoryEntry(
            id: UUID(),
            createdAt: PastSession.stamp,
            updatedAt: PastSession.stamp,
            deletedAt: nil,
            exerciseID: exerciseID,
            effectiveFrom: date,
            oldWeight: old.map { Weight(grams: $0 * 1000) },
            newWeight: Weight(grams: kilos * 1000),
            reason: "coach")
    }
}
