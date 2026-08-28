#if canImport(HealthKit)

    import Foundation
    import HealthKit
    import PowerliftingCore

    /// `FR-1.8.2`'s readings, out of HealthKit and no further (`G-5.4`, `TR-1.9`).
    ///
    /// **Body mass alone.** The authorization asks for one quantity type and nothing to share, so a
    /// person granting it grants a single reading and not a health record.
    ///
    /// **Read-only, on-device, and it goes nowhere.** Every sample this returns is handed to
    /// ``HealthBodyweightImport`` and lands in the same local store `FR-1.8.1`'s typed readings do;
    /// nothing here reaches a network, and `FR-1.12`'s later sync carries the *entry* rather than any
    /// connection to Health.
    public struct HealthBodyweightSource: BodyweightSampleSource {
        /// The type asked for, and the only one.
        private static let bodyMass = HKQuantityType(.bodyMass)

        private let store = HKHealthStore()

        /// Creates the source. Constructing it prompts for nothing; ``authorize()`` is the prompt.
        public init() {}

        /// Whether this device stores health data at all — `false` on hardware that has no Health.
        public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

        /// Asks for read access to body mass. See the protocol on why success is not consent.
        public func authorize() async throws {
            try await store.requestAuthorization(toShare: [], read: [Self.bodyMass])
        }

        /// Every body-mass sample, newest first.
        ///
        /// **Kilograms into whole grams, rounded to nearest** (`G-1.1`): HealthKit answers in a unit
        /// of the caller's choosing as a `Double`, and grams are the only representation stored. A
        /// sample that cannot be one — a value no scale produces — is dropped rather than stored as
        /// something else.
        public func samples() async throws -> [BodyweightSample] {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: Self.bodyMass)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
            return try await descriptor.result(for: store).compactMap { sample in
                let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                guard let weight = Weight(kilograms: kilograms, rounding: .nearest) else {
                    return nil
                }
                return BodyweightSample(id: sample.uuid, date: sample.startDate, weight: weight)
            }
        }
    }

#endif
