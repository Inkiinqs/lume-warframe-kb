# Local API Prototype

This is a dependency-free local HTTP wrapper around the backend knowledge layer.

Start it with:

```powershell
node .\local-api\server.mjs
```

Optional port override:

```powershell
$env:WARFRAME_KB_API_PORT = "4478"
node .\local-api\server.mjs
```

Endpoints:

- `GET /api/health`
- `GET /api/contracts/endpoints`
- `POST /api/assistant/query`
- `GET /api/player/{playerId}/inventory-summary`
- `GET /api/player/{playerId}/live-context`
- `GET /api/player/{playerId}/live-context/poll?since={changeToken}`
- `POST /api/overlay/inventory-sync`
- `POST /api/overlay/loadout-sync`
- `POST /api/overlay/mission-sync`
- `POST /api/overlay/event-feed`

Notes:

- `POST /api/assistant/query` calls `scripts/resolve-assistant-query.ps1`.
- `GET /api/player/{playerId}/inventory-summary` reads `ai/materialized-views/player-owned-summary.view.json`.
- `GET /api/player/{playerId}/live-context` reads `ai/materialized-views/assistant-live-context.view.json`.
- `GET /api/player/{playerId}/live-context/poll` compares a caller `since` token against the current live-context/source-file token and returns either `modified` with context or `not-modified` with no context payload.
- `POST /api/overlay/inventory-sync` returns a safe merge preview by default.
- `POST /api/overlay/loadout-sync` returns a safe preview for current equipped loadout and upgrade-state capture, then can update player session/build-template state when explicitly confirmed.
- `POST /api/overlay/mission-sync` returns a safe preview for current node/faction/objective/modifier context, then can update player session state when explicitly confirmed.
- `POST /api/overlay/event-feed` returns a safe preview for append-only gameplay events, then can append rolling session history when explicitly confirmed.
- Persistent overlay writes require `writeMode: "persistent"`, `confirmWrite: true`, and an `x-warframe-kb-api-key` header matching `WARFRAME_KB_API_KEY`; the API writes backups before changing player inventory, session, or build-template state.
- Confirmed overlay writes automatically attempt to refresh `assistant-live-context.view.json`; write responses include `liveContextRefresh.status`.

Structure:

- `server.mjs`: thin HTTP bootstrap.
- `src/routes.mjs`: endpoint routing.
- `src/services/`: assistant, inventory, session, live-context refresh, overlay inventory, overlay loadout, overlay mission, and overlay event-feed service logic.
- `src/http-utils.mjs`: JSON request/response helpers.
- `src/json-store.mjs`: repository JSON reads.
- `src/powershell.mjs`: bridge to existing PowerShell backend scripts.
