# Architecture

## Purpose

This repository is not just an item dump. It is a structured Warframe knowledge base intended to support:

- AI explanations
- build generation
- farm recommendations
- inventory tracking
- world-state awareness
- future overlay assistance

## Domain Boundaries

### `content/items`

Store playable and collectible entities:

- Warframes
- weapons
- mods
- arcanes
- companions
- vehicles
- relics
- resources

### `content/systems`

Store mechanics and game rules:

- status effects
- damage interactions
- formulas
- modding behavior
- ability rules
- scaling behavior
- mission rules
- drop rules

### `content/activities`

Store game mode knowledge:

- star chart
- open worlds
- railjack
- duviri
- rotating endgame activities

### `content/world`

Store world-model knowledge:

- factions
- enemies
- locations
- tilesets
- syndicates

### `content/relationships`

Store explicit links between records:

- crafting recipes
- drop locations
- item compatibility
- build synergies
- reference mappings

### `player`

Store user-specific state only:

- inventory ownership
- build snapshots
- progression
- mastery
- wishlist
- session traces

### `ai`

Store generated search and retrieval assets:

- prompt-ready summaries
- embeddings
- materialized query views

## Why mechanics live separately

Status effects, damage rules, and formulas should not be duplicated across item files.

For example:

- `content/systems/status-effects/viral.json` explains what Viral does
- item records reference `status.viral` where relevant
- AI views can combine those records later without repeating the mechanic in every weapon or mod

This keeps updates controlled when the game changes.
