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
| `revision` | integer ≥ 1 | Which *edition* of the content it is. Bumped on every published change, including one that leaves `schemaVersion` alone. |
| `exercises` | array | The entries, in authoring order. Order is not a contract: nothing may assume a parent precedes its variations. |

Two numbers rather than one, because one cannot answer both questions. A content edit that bumped a
shared version would lock out every older reader; one that did not would be invisible to the launch
check in `TR-0.5.3`.

## An entry

```json
{
  "id": "11111111-1111-4111-8111-111111111111",
  "name": "Front Squat",
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
| `name` | string | yes | Non-blank. Renaming a built-in exercise later does not break history (`FR-1.1.4`). |
| `movement` | string | yes | A `Movement` raw value. |
| `parentExerciseID` | UUID string | no | The entry this one varies (`FR-1.1.7`). Absent for a root exercise; must name an entry in the same document; the parent chains may not close on themselves. |
| `equipment` | string | yes | An `Equipment` raw value. |
| `laterality` | string | yes | A `Laterality` raw value. |
| `barType` | string | yes | A `BarType` raw value. Required rather than defaulted: an absent value would resolve to a category the author did not choose. An exercise using no bar says `noBar` — not `none`, not `null`, not nothing. |
| `implementCount` | integer ≥ 1 | no | How many implements one rep loads. Absent means one. Say `2` on dumbbell pressing and anything else loading a pair; a logged weight is the load on **one** implement, and this is the factor `FR-1.5.1`'s tonnage needs. Do not infer it from `equipment` or `laterality` — a dumbbell bench press and a goblet squat agree on both and differ on this. |

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
