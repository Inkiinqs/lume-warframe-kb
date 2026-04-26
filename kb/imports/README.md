# Imports

Imports are intentionally separated from canonical content.

- `static/`: source exports for items, missions, and reference content
- `live/`: rotating world-state feeds
- `market/`: trading and economy sources
- `manual/`: curated hand-authored imports
- `overlay-sync/`: future player sync and overlay-derived data

Preferred flow:

1. Pull source data into `imports/`
2. Normalize and validate it
3. Write clean canonical records into `content/` or `player/`
