import { copyRepoFile, writeJson } from "../json-store.mjs";
import { getInventoryRecord, inventoryPathForPlayer } from "./inventory-service.mjs";
import { refreshLiveContextAfterWrite } from "./live-context-refresh-service.mjs";

function timestamp() {
  return new Date().toISOString();
}

function safeTimestamp(value) {
  return value.replace(/[:.]/g, "-");
}

function normalizeRecognizedItems(body) {
  return Array.isArray(body.recognizedItems) ? body.recognizedItems : [];
}

function cloneOwnedEntry(entry) {
  return Object.fromEntries(Object.entries(entry ?? {}));
}

function buildMergePlan(inventory, body) {
  const recognizedItems = normalizeRecognizedItems(body);
  const capturedAt = body.capturedAt ?? timestamp();
  const ownedMap = new Map();

  for (const owned of inventory.data?.owned ?? []) {
    ownedMap.set(owned.itemId, cloneOwnedEntry(owned));
  }

  const mergedItems = [];
  const unknownItems = [];

  for (const item of recognizedItems) {
    if (!item.canonicalItemId) {
      unknownItems.push({
        rawLabel: item.rawLabel ?? "",
        quantity: item.quantity ?? null,
        confidence: item.confidence ?? null
      });
      continue;
    }

    const existing = ownedMap.get(item.canonicalItemId) ?? {
      itemId: item.canonicalItemId,
      quantity: 0
    };
    const previousQuantity = Number.isFinite(existing.quantity) ? existing.quantity : 0;
    const incomingQuantity = Number.isFinite(item.quantity) ? item.quantity : 0;
    const nextQuantity = Math.max(previousQuantity, incomingQuantity);

    mergedItems.push({
      itemId: item.canonicalItemId,
      previousQuantity,
      quantity: nextQuantity,
      changed: nextQuantity !== previousQuantity || existing.lastSeenRawLabel !== item.rawLabel || existing.lastSeenConfidence !== item.confidence,
      lastSeenConfidence: item.confidence ?? null,
      lastSeenRawLabel: item.rawLabel ?? null
    });

    ownedMap.set(item.canonicalItemId, {
      ...existing,
      itemId: item.canonicalItemId,
      quantity: nextQuantity,
      lastSeenConfidence: item.confidence ?? null,
      lastSeenRawLabel: item.rawLabel ?? null,
      lastSeenAt: capturedAt
    });
  }

  return {
    recognizedItems,
    capturedAt,
    ownedAfterMerge: Array.from(ownedMap.values()).sort((a, b) => a.itemId.localeCompare(b.itemId)),
    mergedItems,
    unknownItems
  };
}

function buildResponse(body, status, mergePlan, extra = {}) {
  return {
    schemaVersion: "overlay-inventory-sync-response.v1",
    playerId: body.playerId ?? "player.demo-account",
    status,
    mode: body.mode ?? "delta",
    note: status === "preview"
      ? "Local API returned a merge preview. Send writeMode: \"persistent\" and confirmWrite: true to write inventory."
      : "Persistent inventory merge completed with a backup written first.",
    recognizedCount: mergePlan.recognizedItems.length,
    mergedItems: mergePlan.mergedItems,
    unknownItems: mergePlan.unknownItems,
    ...extra,
    nextActions: status === "preview"
      ? [
          "Review unknownItems and map confident OCR labels to canonical IDs.",
          "Send writeMode: \"persistent\" and confirmWrite: true only when the caller intends to mutate player inventory.",
          "Rebuild player-aware views after a persistent inventory merge."
        ]
      : [
          "Rebuild player-aware views so assistant inventory summaries reflect the write.",
          "Review unknownItems and map confident OCR labels to canonical IDs."
        ]
  };
}

export async function previewOverlayInventorySync(body, options = {}) {
  const playerId = body.playerId ?? "player.demo-account";
  const shouldWrite = body.writeMode === "persistent" && body.confirmWrite === true;
  const inventory = await getInventoryRecord(playerId);
  const mergePlan = buildMergePlan(inventory, body);

  if (!shouldWrite) {
    return buildResponse(body, "preview", mergePlan, {
      writeRequiredFields: {
        writeMode: "persistent",
        confirmWrite: true
      }
    });
  }

  if (!options.canWrite) {
    const error = new Error("Persistent overlay inventory sync requires a valid x-warframe-kb-api-key header.");
    error.statusCode = 403;
    error.details = {
      requiredHeader: "x-warframe-kb-api-key",
      writeMode: "persistent",
      confirmWrite: true
    };
    throw error;
  }

  const inventoryPath = inventoryPathForPlayer(playerId);
  const backupPath = `player/inventory-tracking/backups/${inventory.id}.${safeTimestamp(timestamp())}.json`;
  await copyRepoFile(inventoryPath, backupPath);

  const updatedInventory = {
    ...inventory,
    updatedAt: timestamp(),
    data: {
      ...inventory.data,
      owned: mergePlan.ownedAfterMerge
    },
    sources: [
      {
        type: "overlay-api",
        value: body.syncId ?? `overlay-api.${safeTimestamp(timestamp())}`
      },
      ...(inventory.sources ?? []).filter((source) => source.type !== "overlay-api")
    ]
  };

  await writeJson(inventoryPath, updatedInventory);

  const normalizedPath = `imports/overlay-sync/normalized/local-api-${safeTimestamp(timestamp())}.json`;
  await writeJson(normalizedPath, {
    generatedAt: timestamp(),
    playerId,
    source: body.source ?? "local-api",
    snapshotType: body.snapshotType ?? "inventory",
    capturedAt: mergePlan.capturedAt,
    recognizedItems: normalizeRecognizedItems(body),
    mergedItems: mergePlan.mergedItems,
    unknownItems: mergePlan.unknownItems
  });

  const liveContextRefresh = await refreshLiveContextAfterWrite(playerId, {
    refreshInventoryViews: true
  });

  return buildResponse(body, "merged", mergePlan, {
    inventoryRecord: inventoryPath,
    backupRecord: backupPath,
    normalizedOutput: normalizedPath,
    liveContextRefresh
  });
}
