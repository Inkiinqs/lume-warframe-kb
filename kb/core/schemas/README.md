# Schema Rules

All canonical records should validate against one of the schemas in this folder.

## Required conventions

- IDs use dotted namespaces such as `warframe.excalibur`, `status.viral`, or `enemy.corrupted-heavy-gunner`.
- Filenames use lowercase kebab-case.
- One canonical record per file.
- Use arrays for multi-value relationships instead of comma-delimited strings.
- Put short summaries in `summary` and detailed text in `notes`.

## Schema split

- `entity.schema.json`: items, enemies, factions, syndicates, locations
- `system.schema.json`: status effects, formulas, rules, scaling behavior
- `relationship.schema.json`: drops, crafting, compatibility, synergies
- `player.schema.json`: inventory, builds, progression, wishlists
- `assistant-build-contract.schema.json`: assistant-facing build contract view
- `query-router.schema.json`: query-router route map contract
- `assistant-query-response.schema.json`: resolved assistant response payload contract
- `backend-api-contracts.schema.json`: endpoint-shaped backend API contract index
