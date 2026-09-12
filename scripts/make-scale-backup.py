#!/usr/bin/env python3
"""
T-1.83 / NFR-1.5, NFR-1.6: build the ~15,000-set backup those two requirements are written against.

    scripts/make-scale-backup.py --source <full-backup.json> --out <path> [--sets 15000]
    scripts/make-scale-backup.py --self-test

WHY A SCRIPT AND NOT A TEST. The fixture has to reach the app's own store *on a phone*, and the
only door into that store is `FR-1.11.4`'s restore, which reads a file. Nothing that runs under
`swift test` can put a row on a device — an SPM test bundle cannot be hosted there at all
(measured 2026-09-10: "Tool-hosted testing is unavailable on device destinations"), and the app
target has no test target to host one (`T-1.94`). So the artefact this task needs is a *file*, and
a file is what this writes.

WHY IT REPLICATES A REAL BACKUP RATHER THAN SYNTHESISING ROWS. `NFR-1.5` says "3 years of
synthetic data" and the tempting reading is a row generator. A generator has to reproduce every
wire rule in `RecordCoding.swift` and every referential rule the restore enforces — parents before
children (`T-16.16`), `FR-16.4.2`'s pending sets, the modifier vocabulary — and a fixture that got
one of them wrong would measure a store the app cannot actually hold. Replication inherits all of
it: the output is the input's own shape, so a file this writes restores exactly where the file it
was built from does. It also inherits the distribution that matters to the measurement — how many
exercises, how many sets per session, how the history clusters — which a uniform generator would
flatten into something no lifter has.

WHAT IT DOES NOT INHERIT. The copies are free workouts: every column that gives a session a
position inside a program is cleared. NOT because the reference would dangle — `programRuns` is
carried, so a copy naming one would resolve — but because a run is a *place*: `SessionLocator`
finds a day by `(runID, week, dayIndex)`, and five generations of sessions all claiming week 3
day 2 of the one run would give that lookup five answers to a question with one. The week and day
numbers go with the run for the same reason, and so does `scheduledWorkoutID`; what is left is
what a workout logged outside any program looks like, which is a shape the app already holds. The
catalogue, the settings row and the bodyweight readings are carried once, unreplicated — they are
not what either requirement scales.

IDS ARE DERIVED, NOT RANDOM. Every copied row's id is `uuid5(namespace, original-id + copy-index)`,
so two runs over the same source produce the same file. A measurement you cannot re-take against
the identical store is a measurement you cannot check.
"""

import argparse
import json
import sys
import uuid

# The namespace copied ids are derived under. Arbitrary, fixed, and this file is its only home.
NAMESPACE = uuid.UUID("9F2C1A64-4B3E-4E4E-9E2B-1D6A5C0F7E31")

# Apple reference date, in seconds. Every date in a backup is one of these, so a shift is arithmetic
# on the number rather than a calendar operation.
SECONDS_PER_DAY = 86_400

# The sections that carry the log, in the order the restore needs them to make sense. Only these are
# replicated; every other section is carried once.
LOG_SECTIONS = ("sessions", "entries", "sets")

# Which keys on a replicated row hold a date. `date` is the session's own; everything else in these
# records ends in `At`.
#
# The list is enumerated rather than pattern-matched, and `unlisted_dates` is what makes that safe.
# Its first version claimed a list would make a new date column "fail loudly" and nothing failed:
# the shift is `DATE_KEYS & row.keys()`, which skips an unlisted key in silence. Two were being
# skipped when that was written — `SetEntry.completedAt`, and `WorkoutSession.endedAt` under a name
# no record has ever had — so every copy kept the original's finish time while its start moved
# years back.
DATE_KEYS = frozenset(
    {"date", "createdAt", "updatedAt", "deletedAt", "startedAt", "endedAt", "completedAt"}
)

# The keys that name another row, per section — what has to be remapped in step with the ids.
FOREIGN_KEYS = {"entries": ("sessionID",), "sets": ("entryID",)}

# Cleared on a copy, for the reason in this file's header: a copy is a free workout, and these four
# are what place a session inside a program.
CLEARED_ON_COPY = ("programRunID", "weekNumber", "dayIndex", "scheduledWorkoutID")


def copied_id(original: str, index: int) -> str:
    """The id row `original` takes in copy `index`, uppercased to match the source's own spelling."""
    return str(uuid.uuid5(NAMESPACE, f"{original}#{index}")).upper()


def span_seconds(sessions: list) -> float:
    """How long the source log runs, plus a day so two copies never share a date."""
    dates = [s["date"] for s in sessions if isinstance(s.get("date"), (int, float))]
    if not dates:
        raise SystemExit("make-scale-backup.py: the source has no dated session to measure a span")
    return (max(dates) - min(dates)) + SECONDS_PER_DAY


def unlisted_dates(archive: dict) -> set:
    """Date-shaped keys in the replicated sections that ``DATE_KEYS`` does not name.

    A key ending in `At`, or spelled `date`, holds a date in every record these sections carry.
    Anything matching that and absent from the list would be copied forward unshifted, which is
    what the list is enumerated to prevent — so the enumeration is checked against the file rather
    than trusted.
    """
    found = set()
    for section in LOG_SECTIONS:
        for row in archive.get(section) or []:
            found |= {
                key
                for key in row
                if (key == "date" or key.endswith("At")) and key not in DATE_KEYS
            }
    return found


def replicate(archive: dict, copies: int) -> dict:
    """The source with `copies` extra generations of its log stacked backwards in time."""
    unlisted = unlisted_dates(archive)
    if unlisted:
        raise SystemExit(
            "make-scale-backup.py: unlisted date column(s) "
            + ", ".join(sorted(unlisted))
            + " — add them to DATE_KEYS, or every copy keeps the original's timestamp"
        )
    out = dict(archive)
    shift = span_seconds(archive["sessions"])
    for section in LOG_SECTIONS:
        out[section] = list(archive.get(section) or [])

    for index in range(1, copies + 1):
        offset = shift * index
        for section in LOG_SECTIONS:
            for row in archive.get(section) or []:
                copy = dict(row)
                copy["id"] = copied_id(row["id"], index)
                for key in FOREIGN_KEYS.get(section, ()):
                    if row.get(key) is not None:
                        copy[key] = copied_id(row[key], index)
                for key in DATE_KEYS & copy.keys():
                    if isinstance(copy[key], (int, float)):
                        copy[key] = copy[key] - offset
                for key in CLEARED_ON_COPY:
                    if key in copy:
                        copy[key] = None
                out[section].append(copy)
    return out


def copies_for(archive: dict, target: int) -> int:
    """How many extra generations it takes to reach `target` sets, never fewer than the source has."""
    have = len(archive.get("sets") or [])
    if have == 0:
        raise SystemExit("make-scale-backup.py: the source has no sets to replicate")
    return max(0, -(-target // have) - 1)


def check(archive: dict) -> None:
    """Every id unique and every foreign key resolvable — the two things a bad remap would break."""
    for section in LOG_SECTIONS:
        rows = archive.get(section) or []
        ids = [row["id"] for row in rows]
        if len(set(ids)) != len(ids):
            raise SystemExit(f"make-scale-backup.py: duplicate id in {section}")
    sessions = {row["id"] for row in archive["sessions"]}
    entries = {row["id"] for row in archive["entries"]}
    for row in archive["entries"]:
        if row["sessionID"] not in sessions:
            raise SystemExit("make-scale-backup.py: an entry names a session that is not here")
    for row in archive["sets"]:
        if row["entryID"] not in entries:
            raise SystemExit("make-scale-backup.py: a set names an entry that is not here")


def self_test() -> None:
    """Prove the remap on a source small enough to check by eye, in both directions."""
    source = {
        "contents": "fullBackup",
        "formatVersion": 2,
        "exportedAt": 0,
        "exercises": [{"id": "E1"}],
        # Every date column a session and a set carry, because a fixture stamping one instant
        # cannot tell a shifted column from a skipped one — `endedAt` and `completedAt` were both
        # being skipped under exactly such a fixture.
        "sessions": [
            {
                "id": "S1",
                "date": 100.0,
                "createdAt": 100.0,
                "startedAt": 100.0,
                "endedAt": 105.0,
                "programRunID": "R1",
                "weekNumber": 3,
                "dayIndex": 2,
            }
        ],
        "entries": [{"id": "N1", "sessionID": "S1", "createdAt": 100.0, "exerciseID": "E1"}],
        "sets": [
            {"id": "T1", "entryID": "N1", "createdAt": 100.0, "completedAt": 104.0, "weight": 1000}
        ],
    }
    grown = replicate(source, 2)
    check(grown)
    assert len(grown["sets"]) == 3, grown["sets"]
    assert len(grown["exercises"]) == 1, "the catalogue must not be replicated"
    copy = grown["sessions"][1]
    assert copy["id"] != "S1", "a copy must not reuse an id"
    assert copy["programRunID"] is None, "a copy must not keep the run it was logged in"
    assert copy["weekNumber"] is None and copy["dayIndex"] is None, "nor the place inside it"
    assert copy["date"] < 100.0, "a copy must be older than what it was copied from"
    assert copy["endedAt"] < 105.0, "every date column moves, not only the listed-first ones"
    assert grown["sets"][1]["completedAt"] < 104.0, "a copied set cannot finish when its source did"
    assert grown["sets"][1]["entryID"] == grown["entries"][1]["id"], "the remap must be in step"
    unlisted = dict(source, sets=[dict(source["sets"][0], syncedAt=1.0)])
    try:
        replicate(unlisted, 1)
    except SystemExit as refusal:
        assert "syncedAt" in str(refusal), refusal
    else:
        raise AssertionError("an unlisted date column must stop the run, not be copied forward")
    assert copied_id("S1", 1) == copied_id("S1", 1), "ids must be derived, not random"
    assert copies_for({"sets": [0] * 3000}, 15000) == 4, "3000 x 5 is the first size over 15000"
    assert copies_for({"sets": [0] * 15000}, 15000) == 0, "a source already at target needs none"
    print("make-scale-backup.py: self-test ok")


def main() -> None:
    parser = argparse.ArgumentParser(description="Grow a full backup to a target set count.")
    parser.add_argument("--source", help="a full-backup .json written by the app")
    parser.add_argument("--out", help="where to write the grown file")
    parser.add_argument("--sets", type=int, default=15_000, help="the set count to reach")
    parser.add_argument("--self-test", action="store_true", help="prove the remap and stop")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if not args.source or not args.out:
        parser.error("--source and --out are both required")

    with open(args.source, encoding="utf-8") as handle:
        archive = json.load(handle)
    if archive.get("contents") != "fullBackup":
        raise SystemExit("make-scale-backup.py: the source must be a full backup, not an export")

    copies = copies_for(archive, args.sets)
    grown = replicate(archive, copies)
    check(grown)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(grown, handle)

    print(
        f"make-scale-backup.py: {len(archive['sets'])} sets x {copies + 1} -> "
        f"{len(grown['sets'])} sets, {len(grown['sessions'])} sessions, "
        f"{len(grown['entries'])} entries, {len(grown['exercises'])} exercises\n"
        f"make-scale-backup.py: wrote {args.out}"
    )


if __name__ == "__main__":
    main()
