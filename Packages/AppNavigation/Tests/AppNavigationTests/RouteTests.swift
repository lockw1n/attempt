import Foundation
import Testing

@testable import AppNavigation

/// The route shape is what every feature task extends and what `TR-1.13`'s inventory is derived
/// from, so what a test can hold here is the two claims the shape makes: a route knows its tab, and
/// a route survives being written down.
@Suite("Route shape")
struct RouteTests {
    /// Every case, so a namespace added later without a `tab` answer cannot compile past this list.
    static let exerciseID = UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-1A2B3C4D5E6F") ?? UUID()
    static let sessionID = UUID(uuidString: "7C1D2E3F-4A5B-4C6D-8E9F-0A1B2C3D4E5F") ?? UUID()

    static let all: [Route] = [
        .dashboard(.recentPersonalRecords),
        .training(.activeSession),
        .exerciseLibrary(.exerciseList),
        .exerciseLibrary(.exerciseDetail(exerciseID: exerciseID)),
        .exerciseLibrary(.exerciseCreate),
        .exerciseLibrary(.exerciseEdit(exerciseID: exerciseID)),
        .exerciseLibrary(.exercisePicker),
        .history(.session(sessionID: sessionID)),
        .history(.calendar),
        .settings(.about),
    ]

    /// The keys a route encodes to, outermost first — the case names and the associated-value
    /// label, which is the whole of the persisted format. Each level holds exactly one key, so
    /// reading it back this way asserts nothing about the encoder's per-process key order.
    private static func encodedKeyPath(_ route: Route) throws -> [String] {
        let data = try JSONEncoder().encode(route)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var path: [String] = []
        while object.count == 1, let key = object.keys.first {
            path.append(key)
            guard let next = object[key] as? [String: Any] else { break }
            object = next
        }
        return path
    }

    /// A round trip cannot see a rename — it encodes and decodes with the same spelling, so both
    /// sides move together and every stored stack is silently dropped in the field. Cases are added
    /// to this enum by every feature task, which is what makes the format worth pinning here.
    @Test("the persisted route spellings are pinned")
    func wireFormatIsPinned() throws {
        #expect(
            try Self.encodedKeyPath(.dashboard(.recentPersonalRecords))
                == ["dashboard", "_0", "recentPersonalRecords"]
        )
        #expect(
            try Self.encodedKeyPath(.training(.activeSession))
                == ["training", "_0", "activeSession"]
        )
        #expect(
            try Self.encodedKeyPath(.exerciseLibrary(.exerciseList))
                == ["exerciseLibrary", "_0", "exerciseList"]
        )
        #expect(
            try Self.encodedKeyPath(.exerciseLibrary(.exerciseDetail(exerciseID: Self.exerciseID)))
                == ["exerciseLibrary", "_0", "exerciseDetail", "exerciseID"]
        )
        #expect(
            try Self.encodedKeyPath(.exerciseLibrary(.exerciseCreate))
                == ["exerciseLibrary", "_0", "exerciseCreate"]
        )
        #expect(
            try Self.encodedKeyPath(.exerciseLibrary(.exerciseEdit(exerciseID: Self.exerciseID)))
                == ["exerciseLibrary", "_0", "exerciseEdit", "exerciseID"]
        )
        #expect(
            try Self.encodedKeyPath(.exerciseLibrary(.exercisePicker))
                == ["exerciseLibrary", "_0", "exercisePicker"]
        )
        #expect(
            try Self.encodedKeyPath(.history(.calendar)) == ["history", "_0", "calendar"]
        )
        #expect(
            try Self.encodedKeyPath(.history(.session(sessionID: Self.sessionID)))
                == ["history", "_0", "session", "sessionID"]
        )
        #expect(try Self.encodedKeyPath(.settings(.about)) == ["settings", "_0", "about"])
    }

    /// `D-8`/Q-1.2's split, stated as the mapping the shell actually navigates by. The Train pair is
    /// the interesting row: two feature areas, one tab.
    @Test("each route names the tab that owns it")
    func routesNameTheirTab() {
        #expect(Route.dashboard(.recentPersonalRecords).tab == .home)
        #expect(Route.training(.activeSession).tab == .train)
        #expect(Route.exerciseLibrary(.exerciseDetail(exerciseID: UUID())).tab == .train)
        #expect(Route.history(.session(sessionID: UUID())).tab == .history)
        #expect(Route.settings(.about).tab == .settings)
    }

    /// The payload has to come back, not just the case: a route that decoded to *some* exercise
    /// detail would restore a stack of the right depth pointed at the wrong row.
    @Test("every route round-trips through JSON with its payload intact", arguments: Self.all)
    func routesRoundTrip(route: Route) throws {
        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(Route.self, from: data)
        #expect(decoded == route)
    }

    /// Anchored to a literal on one side: `a == b` between two decodes would be satisfied by any
    /// pair of identical wrong answers.
    @Test("a decoded route carries the identifier it was encoded with")
    func payloadSurvives() throws {
        let id = Self.exerciseID
        let data = try JSONEncoder().encode(Route.exerciseLibrary(.exerciseDetail(exerciseID: id)))
        let decoded = try JSONDecoder().decode(Route.self, from: data)
        guard case .exerciseLibrary(.exerciseDetail(let decodedID)) = decoded else {
            Issue.record("expected an exercise detail route, got \(decoded)")
            return
        }
        #expect(decodedID.uuidString == "0F5A1E24-9B7D-4C31-8E62-1A2B3C4D5E6F")
    }

    /// The closed-vocabulary half of the unknown-value rule: a route this version does not know
    /// throws rather than resolving to something. Degrading happens one level up, in the snapshot,
    /// and it can only happen there if this throws.
    @Test("a route case this version does not know fails to decode")
    func unknownRouteThrows() {
        let json = Data(#"{"crossTraining":{"_0":{"class":{}}}}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Route.self, from: json)
        }
    }
}
