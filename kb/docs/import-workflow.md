# Import Workflow

## Goal

Move upstream data into canonical records without letting raw source structure leak into the repository design.

## Workflow

1. Save raw source snapshots under the appropriate `imports/` domain.
2. Create a manifest using the relevant `manifest.template.json`.
3. Normalize source fields into canonical IDs and record shapes.
4. Write or update records under `content/` or `player/`.
5. Run `scripts/validate-kb.ps1`.
6. Run `scripts/build-registry.ps1`.
7. Review any placeholder records that should now be replaced or removed.

## Normalization rules

- prefer repository IDs over source IDs
- preserve upstream IDs as source metadata when useful
- avoid mixing live data into canonical mechanics
- use relationship records instead of duplicating the same fact in many files

## Import strategy by domain

- `systems`: slower, manual-first, validation-heavy
- `items/world/activities`: import-friendly and good targets for bulk normalization
- `relationships`: generate from normalized facts where possible
- `player`: keep isolated from content truth
