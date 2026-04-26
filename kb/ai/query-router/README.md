# Query Router

This folder stores generated routing metadata for assistant and backend query dispatch.

Files:

- `route-map.json`: intent-to-view routing rules, fallback views, content scopes, and path availability.
- `intents.json`: compact intent catalog for classifier prompts or backend routing code.
- `examples.json`: example utterances with expected intents for tests and prompt tuning.
- `reports/latest.query-router-test-report.json`: optional smoke-test output from `scripts/test-query-router.ps1 -WriteReport`.
- `reports/sample-*-response.json`: optional sample resolver outputs from `scripts/resolve-assistant-query.ps1`.

The router is derived from `scripts/build-query-router.ps1`. Do not hand-author gameplay truth here; add or adjust canonical data under `content/`, player state under `player/`, or generator logic under `scripts/`.

Resolver example:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\resolve-assistant-query.ps1 -Root . -Query "make me a Rhino build for Murmur"
```
