# Overlay Sync Workflow

Overlay and OCR imports should produce player-layer updates, not canonical game records.

Pipeline:

1. Capture OCR or overlay snapshots into `imports/overlay-sync/source-snapshots/`.
2. Normalize and merge them into `player/inventory-tracking/`.
3. Rebuild player-aware views so AI queries can use the latest owned items.

Merge rules:

- Quantities should keep the highest observed trusted quantity per item unless a full inventory snapshot is explicitly marked authoritative.
- Confidence from OCR should be retained in import metadata.
- Unknown item labels should remain in normalized output for manual review instead of being discarded.
