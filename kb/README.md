# Warframe Knowledge Base

This repository is the canonical knowledge layer for the Warframe assistant app.

It is designed to answer two different needs without mixing them together:

- static and live game knowledge
- player-specific inventory, builds, and tracking

## Design Goals

- Keep game content separate from player data.
- Keep mechanics separate from items.
- Keep relationships explicit instead of burying them in free text.
- Keep AI-facing search documents separate from normalized source data.
- Make imports replaceable so the backend can swap sources later.

## Top-Level Layout

- `content/`: all Warframe game knowledge
- `player/`: user-owned state, builds, and progression
- `ai/`: search docs, embeddings, and materialized AI views
- `imports/`: source connectors and import staging
- `core/`: schemas, indexes, naming rules, and repository contracts
- `templates/`: canonical file templates for new data
- `docs/`: human documentation for sources, glossary, and update policy

## Content Model

The knowledge base is intentionally split by purpose:

- `content/items/`: what exists
- `content/systems/`: how the game works
- `content/activities/`: how the player engages with game modes
- `content/world/`: who and where content belongs to
- `content/relationships/`: how entities connect to each other

This separation is the core guardrail against turning the project into one giant item dump.

## Source of Truth Rules

1. `content/` holds canonical game knowledge.
2. `player/` never becomes the source of truth for game mechanics.
3. `ai/` is generated from `content/` and `player/`, not hand-authored.
4. Imports write to staged files first, then normalize into canonical folders.
5. Every record must have a stable internal ID that survives source changes.

## Recommended Build Order

1. Fill core schemas and templates.
2. Populate systems knowledge first for damage, status, scaling, and formulas.
3. Import entity data for items, world content, and activities.
4. Add relationship records for drops, crafting, compatibility, and synergies.
5. Layer player data and AI indexes on top.
2026-04-26T08:06:35Z test bump
