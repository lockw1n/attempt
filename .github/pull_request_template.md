<!--
Keep this short. The point is the two ID fields — everything else is a reminder,
not paperwork. See README → Conventions → "Commits carry requirement IDs".
-->

## What changed

<!-- One or two sentences. -->

## Requirement IDs

<!--
Every PR traces to at least one: G-*, FR-*, NFR-*, TR-*, OUT-*, DOD-*, D-*.
Work with none behind it is scope creep — resolve that rather than inventing an ID.
-->

-

## Task

<!-- e.g. T-0.10, from docs/phase-0/tasks.md. Write "none" for work outside the phase plan. -->

-

## Before merging

- [ ] Commit subjects lead with a requirement ID
- [ ] The task file's scope and "done when" boxes are ticked — or the gaps are
      recorded in its Notes, with the reasoning
- [ ] `docs/phase-0/tasks.md` and `docs/phase-0/coverage.md` reflect the new status
- [ ] Tests exist for the behaviour that changed
- [ ] CI is green, and any job that is green *for the wrong reason* is called out
