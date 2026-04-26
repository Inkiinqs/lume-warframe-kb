import { readJson } from "../json-store.mjs";

export function inventoryPathForPlayer(playerId) {
  const slug = (playerId || "player.demo-account").replace(/^player\./, "");
  return `player/inventory-tracking/${slug}-inventory.json`;
}

export async function getInventoryRecord(playerId) {
  return readJson(inventoryPathForPlayer(playerId));
}

export async function getInventorySummary(playerId) {
  const summary = await readJson("ai/materialized-views/player-owned-summary.view.json");
  if (playerId && summary.playerId !== playerId) {
    return {
      schemaVersion: "player-inventory-summary-response.v1",
      playerId,
      sourceView: "ai/materialized-views/player-owned-summary.view.json",
      items: {},
      warning: `Requested playerId '${playerId}' does not match available summary '${summary.playerId}'.`
    };
  }

  return {
    schemaVersion: "player-inventory-summary-response.v1",
    playerId: summary.playerId,
    generatedAt: summary.generatedAt,
    sourceView: "ai/materialized-views/player-owned-summary.view.json",
    items: summary.items
  };
}
