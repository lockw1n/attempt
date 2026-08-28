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

        /// How far `FR-1.10.4`'s authorization has got — never whether it was granted.
        ///
        /// **`HKHealthStore.authorizationStatus(for:)` is the wrong call and answering it here would
        /// be a lie.** Each of its three cases is about *saving* — "may save objects of the
        /// specified type" — and this source asks to share nothing, so it would answer
        /// `notDetermined` forever whatever the person chose. The request status is the one signal
        /// about a read that HealthKit will part with, and all it says is whether asking again would
        /// still prompt.
        public func authorizationState() async -> BodyweightSourceAuthorization {
            guard isAvailable else { return .unavailable }
            do {
                let status = try await store.statusForAuthorizationRequest(
                    toShare: [], read: [Self.bodyMass])
                switch status {
                case .shouldRequest: return .notAsked
                case .unnecessary: return .answered
                case .unknown: return .unknown
                // A case this build does not know is not a grant, so it reads as the one that
                // claims nothing — the four-way rule's "refuse to guess" answer.
                @unknown default: return .unknown
                }
            } catch {
                // HealthKit already has a case for a request status it could not determine, so a
                // thrown error is that case rather than a second failure mode for a screen to draw.
                return .unknown
            }
        }

        /// Every body-mass sample, newest first.
        ///
        /// **The unit crossing is not here** — this asks HealthKit for kilograms and hands them to
        /// ``BodyweightSample/fromKilograms(_:id:date:)``, which owns `G-1.1`'s rounding and the
        /// refusal. What is left in this method is the query, which no test can reach.
        public func samples() async throws -> [BodyweightSample] {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: Self.bodyMass)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
            return try await descriptor.result(for: store).compactMap { sample in
                BodyweightSample.fromKilograms(
                    sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                    id: sample.uuid,
                    date: sample.startDate)
            }
        }
    }

#endif
