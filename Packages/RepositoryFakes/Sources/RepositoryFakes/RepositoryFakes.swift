// In-memory implementations of the five repository protocols (`TR-0.4.2`), for previews, for
// callers' unit tests, and as the second subject of the conformance suite in this package's tests.
//
// WHAT A FAKE HERE IS FOR. `RepositoryInterface`'s test target already conforms to all five
// protocols; those witnesses prove the protocols are satisfiable and say in their own header that
// they do not honour the contract. These do. The difference is the point of the suite: a fake that
// stores what it is handed passes every test a caller writes and is wrong about deletion,
// timestamps and ordering, and the caller finds out in the app.
//
// THREE RULES EVERY FAKE HERE IMPLEMENTS DELIBERATELY, none of which follows from holding records.
//
// 1. READS RETURN LIVE ROWS. `deletedAt` filters every enumerating read unless `includingDeleted:`
//    says otherwise, deletion is soft, and a second delete of the same row raises
//    `recordNotFound` because the row is no longer live.
// 2. THE AUDIT COLUMNS BELONG TO THE WRITE PATH, NOT TO THE CALLER. A save stamps `updatedAt`
//    (`G-2.4`), ignores the record's `deletedAt`, and honours `createdAt` only when the row is new.
//    ``InMemoryRepositoryStore/upserted(_:into:at:)`` is the one place that happens, the same way
//    `Persistence`'s `upsert(_:as:)` is.
// 3. EVERY LIST IS ORDERED ON A KEY ENDING IN `id.uuidString`. A dictionary's values have no order
//    and Swift's hash seed changes per process, so a fake that returned them would be a different
//    answer every launch.
//
// `InMemoryRepositoryStack` IS THE WHOLE PUBLIC SURFACE, mirroring `PersistenceStack` on the other
// side. The five fakes are `internal` for the same reason the five SwiftData implementations are: a
// consumer holds `any ExerciseRepository`, and a fake that could be named concretely is a fake a
// caller can start depending on the shape of. It also keeps the two subjects of the conformance
// suite the same shape, which is what lets one test body run against both.
//
// NOTHING HERE IS SHARED WITH `Persistence`, AND THAT IS DELIBERATE RATHER THAN LAZY. The feed's
// sort key, the duplicate resolution and the cascade are written twice on purpose: a conformance
// suite whose two subjects call the same code proves that the code runs, not that two
// implementations agree. Where the argument behind a rule lives once — in `Persistence` or in
// `RepositoryInterface`'s header — this side names it and does not restate it.
//
// WHAT THESE FAKES CANNOT REPRESENT, AND WHY THAT IS THE RIGHT SHAPE. Each table is keyed by `id`,
// so two rows sharing one cannot exist here. `G-2.5` forbids the unique constraint, so they can
// exist in the store — but no call on any of the five protocols produces one: every save upserts
// by `id` and `settings()` is find-or-create. A state a caller cannot reach through the protocol is
// a state a fake standing in for the protocol need not model, and keying by `id` makes it
// *unrepresentable* rather than silently mis-answered. The tiebreak that resolves such a pair
// (`G-2.4`) therefore lives in `Persistence` alone, tested there, and is out of the conformance
// suite's scope; the suite's own header lists the four exclusions and what holds each one.
