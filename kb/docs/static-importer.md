# Static Importer

## Purpose

The static importer is the first production-oriented path for moving staged source snapshots into canonical item records.

## Current scope

- warframes
- weapons
- mods
- resources

## How it works

1. stage source arrays under `imports/static/source-snapshots/`
2. list them in a manifest under `imports/static/manifests/`
3. map fields through `core/mappings/static-import.map.json`
4. run `scripts/run-static-pipeline.ps1`

## Preview-first behavior

By default, normalization produces `imports/static/normalized/last-static-normalization.json` and does not overwrite canonical files.

Use `-WriteCanonical` only when you are confident the staged input is ready.

## Supported passthrough fields

The current static importer can preserve:

- `id`
- `slug`
- `name`
- `summary`
- `description`
- `subCategory`
- `aliases`
- `stats`
- `mechanics`
- `relationships`
- `release`
- `tags`
- `notes`

## Next likely upgrades

- source-specific adapters
- manifest-driven domain overrides instead of filename inference
- schema-aware validation by record type
- merge strategy for partial updates instead of simple file replacement
