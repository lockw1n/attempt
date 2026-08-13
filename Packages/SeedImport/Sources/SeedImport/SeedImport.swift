// SeedImport — the bundled catalogue on its way into storage (TR-0.5.1, NFR-1.7, G-2.1, FR-1.1.4).
//
// It maps `SeedContent`'s payload onto `RepositoryInterface`'s records. That mapping exists here
// rather than on either side because neither side may name the other; this package's manifest has
// the argument.
//
// Module-wide rules, stated once here:
//
//   - NOTHING HERE TOUCHES THE NETWORK. `NFR-1.7` puts first launch after install in airplane mode
//     with nothing to fall back to, so the import reads the app bundle and only the app bundle. It
//     is not a preference this module happens to hold: `no_networking_in_seed_import` fails the
//     build on a fetch anywhere under this package, and that rule's entry in `.swiftlint.yml`
//     carries the argument and the shapes it covers.
//
//   - VALIDATE BEFORE WRITING ANYTHING. `SeedCatalogueValidator` over the bytes, and an empty
//     result is the only passing result. A malformed payload must cost nothing, so the check
//     happens before the first save rather than per entry — a half-applied catalogue on first
//     launch is the failure `NFR-1.7` has no recovery from.
//
//   - `isCustom` DECIDES WHETHER A ROW MAY BE OVERWRITTEN, and `Exercise` says so on the property
//     itself. A row the user authored is never written by an import, whatever its id.
//
//   - THE SEED OWNS SOME COLUMNS AND THE ROW OWNS THE REST. Which are which, and why each falls
//     where it does, is `Exercise.reseeded(from:)`'s doc comment — the split is that method's whole
//     body, so listing it a second time here is two copies to keep in step.
//
//   - A SAVE THAT CHANGES NOTHING IS STILL A WRITE, so this module does not make one. Every
//     repository stamps `updatedAt` on the way in whatever the record said, and `updatedAt` is
//     `G-2.4`'s conflict key — so an unconditional re-save of 116 rows would let a launch outrank a
//     real remote edit on every one of them. Each row is compared with what the import would write
//     and saved only when the two differ.
//
//   - THE PAYLOAD'S ORDER IS NOT AN IMPORT ORDER. `SeedCatalogue.exercises` is in authoring order
//     and says so; `save` refuses a `parentExerciseID` naming a row that does not exist yet, so a
//     variation authored above its parent would fail on the first entry. Sorting is this module's,
//     and `SeedExerciseOrdering` is where it happens.
