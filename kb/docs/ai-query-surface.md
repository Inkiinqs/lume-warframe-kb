# AI Query Surface

## Purpose

These derived files give the assistant a fast query layer without making it scan the entire repository every time.

## Search docs

- `ai/search-docs/records.search.json`

Each entry contains:

- record ID
- name
- category
- source path
- flattened text for retrieval

## Materialized views

- `ai/materialized-views/item-to-parts.view.json`
- `ai/materialized-views/part-to-sources.view.json`
- `ai/materialized-views/relic-to-rewards.view.json`
- `ai/materialized-views/part-to-relics.view.json`
- `ai/materialized-views/player-missing-targets.view.json`

These are designed to answer:

- what parts does item X need
- where can part Y drop
- which relics contain part Z
- what does relic R reward
- what is this player missing for target T
- which missing parts are currently accessible to this player

## Build flow

Run:

`powershell -ExecutionPolicy Bypass -File .\scripts\build-ai-layer.ps1 -Root .`

after major content or relationship updates.
