# `exercises.json`

The bundled seed catalogue (`TR-0.5.1`), and the payload published at `/content/v1/exercises.json`
(`TR-0.5.2`). One document, two delivery routes — so the shape below is a public contract, not an
internal detail.

Validate before shipping either copy:

```swift
let failures = SeedCatalogueValidator.validate(try Data(contentsOf: url), minimumExercises: 80)
```

An empty result is the only passing result. Every failure prints a line naming the entry.

## The document

```json
{
  "schemaVersion": 1,
  "revision": 1,
  "exercises": [ … ]
}
```

| Key | Type | |
|---|---|---|
| `schemaVersion` | integer | Which *shape* the document is in. Bumped only when a reader of the previous version could not cope. A reader refuses a version it does not know. |
| `revision` | integer ≥ 1 | Which *edition* of the content it is. Bumped on every published change, including one that leaves `schemaVersion` alone. **A device refuses a served payload whose revision is not higher than the one it already holds**, so an edit that forgets the bump cannot reach an install that cached the previous edition — the bundled copy's number is pinned by a test for that reason. |
| `exercises` | array | The entries, in authoring order. Order is not a contract: nothing may assume a parent precedes its variations. |

Two numbers rather than one, because one cannot answer both questions. A content edit that bumped a
shared version would lock out every older reader; one that did not would be invisible to the launch
check in `TR-0.5.3`.

## An entry

```json
{
  "id": "11111111-1111-4111-8111-111111111111",
  "name": "Front Squat",
  "ukrainianName": "Фронтальні присідання",
  "movement": "squat",
  "parentExerciseID": "22222222-2222-4222-8222-222222222222",
  "equipment": "barbell",
  "laterality": "bilateral",
  "barType": "standard",
  "implementCount": 2
}
```

| Key | Type | Required | |
|---|---|---|---|
| `id` | UUID string | yes | **Permanent.** It lands in users' logged history, so regenerating one orphans every set logged against it. |
| `name` | string | yes | Non-blank, **which the validator enforces**. A lifter may rename a built-in exercise (`FR-1.1.4`), and a later revision **never overwrites a stored name** — correcting one is done through `formerNames` below and no other way. |
| `ukrainianName` | string | no | The displayed name in Ukrainian (`FR-1.14.2`); absent is a name the app shows in English. Name the movement and the implement, **never the muscle** (`OUT-18.1`). **The validator does not read this key**, so nothing refuses a blank or untranslated one on either route: the shipped catalogue is held to a translation on every entry by its own tests, and a fetched payload is held to nothing. |
| `formerNames` | array of strings | no | Names this entry used to ship under (`FR-18.2.1`). On import a stored name is replaced by `name` only where it still **equals** one of these, trimmed, matching case and diacritics exactly — so a lifter's own rename survives and a correction still reaches phones that already seeded the old one. **Only the row sharing this entry's `id` is ever rewritten**: the importer resolves the stored row by id and compares names only within it, so a former name cannot reach a different exercise that happens to read alike. Each must be non-blank, **which the validator enforces**; none should be any entry's current `name`, which it does not — a still-live former name is an authoring mistake leaving two rows that read alike, and only a test over the shipped catalogue catches it. |
| `formerUkrainianNames` | array of strings | no | The same, for `ukrainianName`. The two lists are per-language and never cross. |
| `movement` | string | yes | A `Movement` raw value. |
| `parentExerciseID` | UUID string | no | The entry this one varies (`FR-1.1.7`). Absent for a root exercise; must name an entry in the same document; the parent chains may not close on themselves. |
| `equipment` | string | yes | An `Equipment` raw value. |
| `laterality` | string | yes | A `Laterality` raw value. |
| `barType` | string | yes | A `BarType` raw value. Required rather than defaulted: an absent value would resolve to a category the author did not choose. An exercise using no bar says `noBar` — not `none`, not `null`, not nothing. |
| `implementCount` | integer ≥ 1 | no | How many implements one rep loads. Absent means one. Say `2` on dumbbell pressing and anything else loading a pair; a logged weight is the load on **one** implement, and this is the factor `FR-1.5.1`'s tonnage needs. Do not infer it from `equipment` or `laterality` — a dumbbell bench press and a goblet squat agree on both and differ on this. |

It is what one *rep* loads, which is what decides the `alternating` case: a walking lunge carries
both dumbbells through every rep and says `2`, an alternating curl moves one and says nothing. The
distinction is not what the lifter is holding — it is what the rep is working against, because
tonnage multiplies this by the reps and by the sides.

A key not listed above is rejected rather than ignored, because a typo that decoded silently would
produce a valid-looking catalogue with a fact missing from it.

## The four vocabularies

**The accepted spellings are not written down here.** They are the raw values of `PowerliftingCore`'s
`Movement`, `Equipment`, `Laterality` and `BarType`, and the validator resolves against those types —
a second copy of the lists is how a schema document and the code it describes drift apart. Run the
validator on a wrong spelling and it prints the accepted set for that field.

Two things the lists do not make obvious:

- `other` is a legitimate authored value, used for accessories. It is also what three of the four
  types resolve an unrecognised spelling to *when decoding a stored row* — which is why validation
  is a separate pass and not a decode. Authoring `other` is fine; authoring a misspelling is not,
  and only this validator can tell them apart.
- A `BarType` is a *category* and never a mass. Bar and collar weight are per-gym and per-user, and
  live on the equipment profile (`FR-1.4.2`, `TR-0.3.7`).

## What is not here

No `createdAt`, no `updatedAt`, no `deletedAt`, no `isCustom`, no `isArchived`, no `notes`. Those are
the stored row's, supplied by the importer — a seed file authoring eighty timestamps would be
authoring eighty fictions.
