# Overlay Sync Imports

Use this folder for player or overlay-derived raw inputs.

Structure:

- `manifests/` describes one import batch for a specific player.
- `source-snapshots/` stores raw OCR or overlay captures.
- `normalized/` stores cleaned snapshots and unresolved labels for review.

Examples:

- OCR outputs
- inventory snapshots
- equipment recognition
- session-derived tracking

Overlay sync should write into player-layer records, not canonical game knowledge.
