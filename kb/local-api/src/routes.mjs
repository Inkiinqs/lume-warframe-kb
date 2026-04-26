import { config } from "./config.mjs";
import { getSessionContext, hasWriteAccess } from "./auth.mjs";
import { readJson } from "./json-store.mjs";
import { readRequestJson, sendError, sendJson } from "./http-utils.mjs";
import { resolveAssistantQuery } from "./services/assistant-service.mjs";
import { getInventorySummary } from "./services/inventory-service.mjs";
import { getLiveContext, pollLiveContext } from "./services/live-context-service.mjs";
import { previewOverlayInventorySync } from "./services/overlay-service.mjs";
import { previewOverlayLoadoutSync } from "./services/loadout-service.mjs";
import { previewOverlayMissionSync } from "./services/mission-service.mjs";
import { previewOverlayEventFeed } from "./services/event-feed-service.mjs";

export async function handleRequest(req, res) {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
  const pathname = url.pathname;
  const session = getSessionContext(req);

  try {
    if (req.method === "GET" && pathname === "/api/health") {
      sendJson(res, 200, {
        schemaVersion: "local-api-health.v1",
        status: "ok",
        repoRoot: config.repoRoot,
        endpoints: [
          "POST /api/assistant/query",
          "GET /api/player/{playerId}/inventory-summary",
          "GET /api/player/{playerId}/live-context",
          "GET /api/player/{playerId}/live-context/poll",
          "POST /api/overlay/inventory-sync",
          "POST /api/overlay/loadout-sync",
          "POST /api/overlay/mission-sync",
          "POST /api/overlay/event-feed"
        ]
      });
      return;
    }

    if (req.method === "GET" && pathname === "/api/contracts/endpoints") {
      sendJson(res, 200, await readJson("backend-api-contracts/endpoints.json"));
      return;
    }

    if (req.method === "POST" && pathname === "/api/assistant/query") {
      sendJson(res, 200, await resolveAssistantQuery(await readRequestJson(req)));
      return;
    }

    const inventoryMatch = pathname.match(/^\/api\/player\/([^/]+)\/inventory-summary$/);
    if (req.method === "GET" && inventoryMatch) {
      sendJson(res, 200, await getInventorySummary(decodeURIComponent(inventoryMatch[1])));
      return;
    }

    const liveContextMatch = pathname.match(/^\/api\/player\/([^/]+)\/live-context$/);
    if (req.method === "GET" && liveContextMatch) {
      sendJson(res, 200, await getLiveContext(decodeURIComponent(liveContextMatch[1])));
      return;
    }

    const liveContextPollMatch = pathname.match(/^\/api\/player\/([^/]+)\/live-context\/poll$/);
    if (req.method === "GET" && liveContextPollMatch) {
      sendJson(res, 200, await pollLiveContext(
        decodeURIComponent(liveContextPollMatch[1]),
        url.searchParams.get("since") ?? ""
      ));
      return;
    }

    if (req.method === "POST" && pathname === "/api/overlay/inventory-sync") {
      sendJson(res, 200, await previewOverlayInventorySync(await readRequestJson(req), {
        canWrite: hasWriteAccess(session),
        session
      }));
      return;
    }

    if (req.method === "POST" && pathname === "/api/overlay/loadout-sync") {
      sendJson(res, 200, await previewOverlayLoadoutSync(await readRequestJson(req), {
        canWrite: hasWriteAccess(session),
        session
      }));
      return;
    }

    if (req.method === "POST" && pathname === "/api/overlay/mission-sync") {
      sendJson(res, 200, await previewOverlayMissionSync(await readRequestJson(req), {
        canWrite: hasWriteAccess(session),
        session
      }));
      return;
    }

    if (req.method === "POST" && pathname === "/api/overlay/event-feed") {
      sendJson(res, 200, await previewOverlayEventFeed(await readRequestJson(req), {
        canWrite: hasWriteAccess(session),
        session
      }));
      return;
    }

    sendError(res, 404, "Route not found.", { method: req.method, path: pathname });
  } catch (error) {
    sendError(res, error.statusCode ?? 500, error.message, error.details ?? {});
  }
}
