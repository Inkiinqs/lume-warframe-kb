# Market Ingestion

Market data stays separate from canonical item identity.

Pipeline:

1. Stage item requests in a market import manifest.
2. Fetch raw snapshots into `imports/market/source-snapshots/`.
3. Normalize raw snapshots into `imports/market/normalized/`.
4. Build AI-facing summaries in `ai/materialized-views/market-summary.view.json`.

Notes:

- The live market endpoint may rate limit or block generic clients. The fetch script records failures as structured snapshot metadata instead of breaking the pipeline.
- Normalized market output is optional enrichment and should not be required for canonical item queries.
- Canonical item resolution should always be stored as `canonicalItemId`.
