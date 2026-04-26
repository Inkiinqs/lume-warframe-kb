# Scripts

This folder now contains starter tooling for repository hygiene and future imports.

## Current scripts

- `validate-kb.ps1`: verifies that repository JSON files parse cleanly
- `build-registry.ps1`: refreshes manifest references in `core/indexes/registry.json`
- `normalize-import.ps1`: placeholder entry point for source-specific normalization
- `normalize-static-import.ps1`: config-driven static import preview/writer
- `run-static-pipeline.ps1`: normalize, validate, and rebuild indexes in one pass
- `build-domain-manifests.ps1`: refreshes leaf-folder manifests from actual record files
- `generate-wfcd-relationships.ps1`: derives parts, crafting links, drops, and relic rewards from WFCD data
- `normalize-drop-locations.ps1`: converts parseable WFCD drop source strings into canonical activity/location or relic IDs
- `build-ai-search-docs.ps1`: generates flattened search documents from canonical content
- `build-ai-views.ps1`: generates query-first materialized views for crafting and farming
- `build-combat-views.ps1`: generates faction and enemy matchup views for build reasoning
- `build-recommendation-views.ps1`: generates player-aware combat recommendation views from matchups and mod roles
- `build-player-build-skeletons.ps1`: generates target-aware starter build skeletons from owned frames, weapons, and mods
- `build-assistant-contracts.ps1`: generates stable assistant-facing response contracts for build and inventory questions
- `build-assistant-live-context.ps1`: generates a fused live overlay assistant context view from session, inventory, loadout, events, and combat recommendations
- `build-query-router.ps1`: generates intent-to-view route maps for assistant/backend query dispatch
- `test-query-router.ps1`: smoke-tests generated router examples against deterministic routing rules
- `resolve-assistant-query.ps1`: prototype resolver that turns a query string into a routed assistant response JSON payload
- `validate-assistant-contracts.ps1`: validates assistant/router schema files and generated response contracts
- `validate-backend-api-contracts.ps1`: validates endpoint-shaped backend API contracts and examples
- `test-backend-api-contracts.ps1`: starts the local API and compares actual endpoint responses to contract examples
- `test-local-api.ps1`: starts the local API prototype and smoke-tests the contract endpoints
- `test-overlay-write-mode.ps1`: verifies confirmed persistent overlay inventory writes using a temporary test player
- `test-overlay-loadout-sync.ps1`: verifies confirmed persistent overlay loadout/session/build writes using a temporary test player
- `test-overlay-mission-sync.ps1`: verifies confirmed persistent overlay mission/session writes using a temporary test player
- `test-overlay-event-feed.ps1`: verifies confirmed persistent overlay event-feed/session writes using a temporary test player
- `test-live-context-auto-refresh.ps1`: verifies confirmed demo overlay writes refresh live assistant context and change-token polling
- `build-backend-readiness-report.ps1`: generates a checkpoint report for backend layers, endpoints, validation status, and known gaps
- `build-market-views.ps1`: generates market summary materialized views from normalized snapshots
- `build-ai-layer.ps1`: rebuilds the full AI layer, validates contracts, tests routing, generates readiness, and validates repository JSON
- `build-player-views.ps1`: generates player-aware missing-target and farmability views
- `apply-system-source-map.ps1`: refreshes source and verification metadata across mechanics records
- `fetch-market-snapshots.ps1`: attempts live market fetches and stores structured success or failure snapshots
- `normalize-market-snapshots.ps1`: consolidates raw market snapshots into per-item summaries
- `import-overlay-inventory.ps1`: merges overlay or OCR snapshots into player inventory and review files

## Intended flow

1. fetch source data into `imports/`
2. create or update an import manifest
3. normalize into canonical records
4. validate repository JSON
5. rebuild registry indexes

For static imports, `run-static-pipeline.ps1` is the preferred entry point.

These scripts are intentionally lightweight so the structure can stabilize before source-specific logic is added.
