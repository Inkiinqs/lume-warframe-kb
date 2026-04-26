# Naming Conventions

## File naming

- Use lowercase kebab-case filenames.
- Use one canonical record per file.
- Match the filename to the record slug where practical.

Examples:

- `content/items/warframes/excalibur.json`
- `content/systems/status-effects/viral.json`
- `content/world/enemies/corrupted-heavy-gunner.json`

## ID naming

Use dotted namespaces:

- `warframe.excalibur`
- `weapon.ignis-wraith`
- `mod.condition-overload`
- `status.slash`
- `damage.viral`
- `enemy.corrupted-heavy-gunner`
- `faction.grineer`
- `activity.steel-path`
- `relationship.drop-ash-systems-rotation-c`

## Relationship IDs

Use a short declarative format:

- `relationship.drop-neurodes-earth-coba`
- `relationship.craft-ignis-wraith-blueprint`
- `relationship.compatibility-serration-rifles`

## Reserved fields

- `summary`: one short AI-safe description
- `description`: longer factual description
- `notes`: extra nuance, caveats, and patch-specific commentary
- `sources`: factual provenance
