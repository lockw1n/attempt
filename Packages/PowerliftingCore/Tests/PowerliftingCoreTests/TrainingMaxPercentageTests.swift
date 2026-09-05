import Testing

@testable import PowerliftingCore

@Suite("Load as a percentage of a training max")
struct TrainingMaxPercentageTests {
    private let trainingMax = Weight(grams: 180_000)

    @Test("An exact share is that share")
    func exactShare() {
        #expect(Weight(grams: 90_000).percentOfTrainingMax(trainingMax) == 50)
        #expect(Weight(grams: 180_000).percentOfTrainingMax(trainingMax) == 100)
        #expect(Weight(grams: 207_000).percentOfTrainingMax(trainingMax) == 115)
    }

    @Test("It rounds to the nearest whole percent")
    func roundsToWholePercent() {
        // 155.2 kg of 180 is 86.222…%, 157.0 kg is 87.2…%, 158.0 kg is 87.7…%.
        #expect(Weight(grams: 155_200).percentOfTrainingMax(trainingMax) == 86)
        #expect(Weight(grams: 157_000).percentOfTrainingMax(trainingMax) == 87)
        #expect(Weight(grams: 158_000).percentOfTrainingMax(trainingMax) == 88)
    }

    @Test("A half percent goes away from zero, in both directions")
    func halfGoesAwayFromZero() {
        // 87.5% of 200 kg is exactly 175 kg — a half-way case that exists in whole grams.
        let twoHundred = Weight(grams: 200_000)
        #expect(Weight(grams: 175_000).percentOfTrainingMax(twoHundred) == 88)
        #expect(Weight(grams: -175_000).percentOfTrainingMax(twoHundred) == -88)
        // And the same case one percent lower, so the assertion above is not merely "rounds up".
        #expect(Weight(grams: 173_000).percentOfTrainingMax(twoHundred) == 87)
    }

    @Test("Assisted work reads as a negative share")
    func assistedWork() {
        #expect(Weight(grams: -18_000).percentOfTrainingMax(trainingMax) == -10)
    }

    @Test("A zero or negative training max has no percentage to state")
    func refusesUnusableTrainingMax() {
        #expect(Weight(grams: 90_000).percentOfTrainingMax(.zero) == nil)
        #expect(Weight(grams: 90_000).percentOfTrainingMax(Weight(grams: -180_000)) == nil)
    }

    @Test("A load whose hundredfold does not fit answers nothing rather than wrapping")
    func refusesOverflow() {
        #expect(Weight(grams: Int.max).percentOfTrainingMax(trainingMax) == nil)
    }

    @Test("Zero is zero percent of a real training max")
    func zeroLoad() {
        #expect(Weight.zero.percentOfTrainingMax(trainingMax) == 0)
    }
}
