# Core Contracts

The `core/` folder defines the rules every other folder follows.

- `schemas/`: JSON Schema contracts for content and player records
- `indexes/`: registry files and future generated lookup indexes
- `items/`, `systems/`, `activities/`, `world/`, `player/`, `ai/`: reserved space for domain-wide configuration if needed later

Do not store gameplay facts here. Store the rules for how gameplay facts are shaped here.
