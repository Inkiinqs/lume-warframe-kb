import { copyRepoFile, writeJson } from "../json-store.mjs";
import { defaultPlayerId, getSessionRecord, readOptionalJson, safeTimestamp, timestamp } from "./session-service.mjs";
import { refreshLiveContextAfterWrite } from "./live-context-refresh-service.mjs";

const MAX_SESSION_EVENTS = 200;
const MAX_RECENT_DROPS = 25;

function normalizeEvent(rawEvent, index, body) {
  const occurredAt = rawEvent.occurredAt ?? body.capturedAt ?? timestamp();
  const eventType = rawEvent.eventType ?? rawEvent.type ?? "overlay.ocr";
  const eventId = rawEvent.eventId ?? `${eventType}.${safeTimestamp(occurredAt)}.${index + 1}`;

  return {
    eventId,
    eventType,
    occurredAt,
    source: rawEvent.source ?? body.source ?? "local-api",
    confidence: rawEvent.confidence ?? null,
    activityId: rawEvent.activityId ?? body.activityId ?? body.mission?.activityId ?? null,
    itemId: rawEvent.itemId ?? rawEvent.canonicalItemId ?? null,
    quantity: rawEvent.quantity ?? null,
    objective: rawEvent.objective ?? null,
    phase: rawEvent.phase ?? null,
    severity: rawEvent.severity ?? null,
    rawText: rawEvent.rawText ?? null,
    payload: rawEvent.payload ?? {}
  };
}

function normalizeEvents(body) {
  return (Array.isArray(body.events) ? body.events : [])
    .map((event, index) => normalizeEvent(event, index, body));
}

function buildRecentDrops(existingDrops, events) {
  const eventDropIds = events
    .filter((event) => ["pickup", "reward", "drop"].includes(event.eventType))
    .map((event) => event.itemId)
    .filter(Boolean);

  return Array.from(new Set([...eventDropIds, ...(existingDrops ?? [])])).slice(0, MAX_RECENT_DROPS);
}

function mergeEvents(existingEvents, incomingEvents) {
  const byId = new Map();
  for (const event of [...incomingEvents, ...(existingEvents ?? [])]) {
    if (!byId.has(event.eventId)) {
      byId.set(event.eventId, event);
    }
  }

  return Array.from(byId.values())
    .sort((a, b) => String(b.occurredAt).localeCompare(String(a.occurredAt)))
    .slice(0, MAX_SESSION_EVENTS);
}

function summarizeEvents(events) {
  const byType = {};
  for (const event of events) {
    byType[event.eventType] = (byType[event.eventType] ?? 0) + 1;
  }
  return {
    total: events.length,
    byType
  };
}

function buildResponse(body, status, details, extra = {}) {
  return {
    schemaVersion: "overlay-event-feed-response.v1",
    playerId: defaultPlayerId(body),
    status,
    mode: body.mode ?? "append",
    note: status === "preview"
      ? "Local API returned an event-feed append preview. Send writeMode: \"persistent\" and confirmWrite: true to append events to player session history."
      : "Persistent event-feed append completed with a backup written first.",
    acceptedEvents: details.acceptedEvents,
    eventSummary: summarizeEvents(details.acceptedEvents),
    sessionEventLimit: MAX_SESSION_EVENTS,
    records: {
      session: details.sessionPath
    },
    changes: details.changes,
    ...extra,
    nextActions: status === "preview"
      ? [
          "Review event types, item IDs, objective progress, and OCR confidence before writing.",
          "Send writeMode: \"persistent\" and confirmWrite: true only when the caller intends to append session event history.",
          "Use event-feed history to drive live overlay assistant suggestions."
        ]
      : [
          "Use recent overlayEvents with currentMission and currentLoadout for live assistant context.",
          "Promote repeated OCR labels into canonical item/activity mappings when confidence is high."
        ]
  };
}

export async function previewOverlayEventFeed(body, options = {}) {
  const playerId = defaultPlayerId(body);
  const shouldWrite = body.writeMode === "persistent" && body.confirmWrite === true;
  const acceptedEvents = normalizeEvents(body);
  const session = await getSessionRecord(playerId);
  const mergedEvents = mergeEvents(session.record.data?.overlayEvents, acceptedEvents);
  const recentDropsSeen = buildRecentDrops(session.record.data?.recentDropsSeen, acceptedEvents);
  const changes = {
    acceptedEventCount: acceptedEvents.length,
    sessionEventCountAfterMerge: mergedEvents.length,
    recentDropsChanged: JSON.stringify(session.record.data?.recentDropsSeen ?? []) !== JSON.stringify(recentDropsSeen)
  };
  const details = {
    acceptedEvents,
    mergedEvents,
    recentDropsSeen,
    sessionPath: session.path,
    changes
  };

  if (!shouldWrite) {
    return buildResponse(body, "preview", details, {
      writeRequiredFields: {
        writeMode: "persistent",
        confirmWrite: true
      }
    });
  }

  if (!options.canWrite) {
    const error = new Error("Persistent overlay event feed requires a valid x-warframe-kb-api-key header.");
    error.statusCode = 403;
    error.details = {
      requiredHeader: "x-warframe-kb-api-key",
      writeMode: "persistent",
      confirmWrite: true
    };
    throw error;
  }

  const now = timestamp();
  const safeNow = safeTimestamp(now);
  const existingSession = await readOptionalJson(session.path);
  const sessionBackup = `player/sessions/backups/${session.record.id}.${safeNow}.json`;
  if (existingSession) {
    await copyRepoFile(session.path, sessionBackup);
  }

  const sourceRecord = {
    type: "overlay-api",
    value: body.syncId ?? `overlay-event-feed-api.${safeNow}`
  };
  const updatedSession = {
    ...session.record,
    updatedAt: now,
    data: {
      ...(session.record.data ?? {}),
      overlayEvents: mergedEvents,
      recentDropsSeen
    },
    sources: [
      sourceRecord,
      ...(session.record.sources ?? []).filter((source) => source.type !== "overlay-api")
    ]
  };

  await writeJson(session.path, updatedSession);

  const normalizedPath = `imports/overlay-sync/normalized/local-api-event-feed-${safeNow}.json`;
  await writeJson(normalizedPath, {
    generatedAt: now,
    playerId,
    source: body.source ?? "local-api",
    snapshotType: body.snapshotType ?? "event-feed",
    capturedAt: body.capturedAt ?? now,
    acceptedEvents,
    eventSummary: summarizeEvents(acceptedEvents),
    records: {
      session: session.path
    }
  });

  const liveContextRefresh = await refreshLiveContextAfterWrite(playerId);

  return buildResponse(body, "merged", details, {
    backupRecord: existingSession ? sessionBackup : null,
    normalizedOutput: normalizedPath,
    liveContextRefresh
  });
}
