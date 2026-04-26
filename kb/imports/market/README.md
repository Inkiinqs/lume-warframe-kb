# Market Imports

Use this folder for economy and trading snapshots.

Structure:

- `manifests/` defines which items and snapshot types to fetch.
- `source-snapshots/` stores raw live or staged responses.
- `normalized/` stores per-item summaries for the AI/backend layer.

Examples:

- price summaries
- volume snapshots
- buy and sell spread data

Market data should remain separate from canonical item identity.
