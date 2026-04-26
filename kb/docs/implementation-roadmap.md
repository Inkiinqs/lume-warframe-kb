# Implementation Roadmap

## Phase 1: foundation

- keep schemas stable
- finalize ID namespaces
- decide import source priority
- add validator and index generator scripts

## Phase 2: systems first

Populate these folders before bulk item imports:

- `content/systems/status-effects/`
- `content/systems/damage/`
- `content/systems/combat-formulas/`
- `content/systems/modding-rules/`
- `content/systems/ability-rules/`

This gives the assistant a reasoning layer before it starts answering build questions.

## Phase 3: entity imports

Populate:

- `content/items/`
- `content/world/`
- `content/activities/`

Normalize everything into canonical IDs rather than trusting source IDs blindly.

## Phase 4: relationships

Populate:

- `content/relationships/crafting/`
- `content/relationships/drops/`
- `content/relationships/compatibility/`
- `content/relationships/synergies/`

This is what makes the backend useful for farming, buildcraft, and recommendations.

## Phase 5: player and AI layers

Populate:

- `player/`
- `ai/search-docs/`
- `ai/materialized-views/`

At this stage the assistant can move from encyclopedia answers to personalized help.

## Phase 6: replace placeholders with imports

- prioritize sourced upgrades for systems, relics, and drop data
- refresh manifests from import runs
- use validation before trusting records in production
