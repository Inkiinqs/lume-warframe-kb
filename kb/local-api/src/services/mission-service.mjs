import { readdir } from "node:fs/promises";
import { copyRepoFile, readJson, writeJson } from "../json-store.mjs";
import { repoPath } from "../config.mjs";
import { defaultPlayerId, getSessionRecord, readOptionalJson, safeTimestamp, timestamp } from "./session-service.mjs";
import { refreshLiveContextAfterWrite } from "./live-context-refresh-service.mjs";

async function listJsonRecordsRecursive(relativeDirectory) {
  const directory = repoPath(...relativeDirectory.split("/"));
  const entries = await readdir(directory, { withFileTypes: true });
  const paths = [];

  for (const entry of entries) {
    const childRelative = `${relativeDirectory}/${entry.name}`;
    if (entry.isDirectory()) {
      paths.push(...await listJsonRecordsRecursive(childRelative));
    } else if (entry.isFile() && entry.name.endsWith(".json")) {
      paths.push(childRelative);
    }
  }

  return paths;
}

async function findActivityRecord(activityId) {
  if (!activityId) {
    return null;
  }

  for (const candidatePath of await listJsonRecordsRecursive("content/activities")) {
    const candidate = await readJson(candidatePath);
    if (candidate.id === activityId) {
      return {
        path: candidatePath,
        id: candidate.id,
        name: candidate.name ?? null,
        tags: candidate.tags ?? [],
        relationships: candidate.relationships ?? []
      };
    }
  }

  return null;
}

function normalizeMission(body, activityRecord) {
  const mission = body.mission ?? {};
  return {
    capturedAt: body.capturedAt ?? timestamp(),
    source: body.source ?? "local-api",
    snapshotType: body.snapshotType ?? "mission",
    activityId: mission.activityId ?? null,
    activityName: mission.activityName ?? activityRecord?.name ?? null,
    nodeName: mission.nodeName ?? null,
    locationId: mission.locationId ?? null,
    factionId: mission.factionId ?? null,
    missionType: mission.missionType ?? null,
    objective: mission.objective ?? null,
    difficultyLevel: mission.difficultyLevel ?? null,
    steelPath: mission.steelPath === true,
    arbitration: mission.arbitration === true,
    fissure: mission.fissure ?? null,
    modifiers: Array.isArray(mission.modifiers) ? mission.modifiers : [],
    squad: mission.squad ?? null,
    timers: mission.timers ?? null,
    recognizedText: Array.isArray(mission.recognizedText) ? mission.recognizedText : []
  };
}

function buildChanges(sessionRecord, currentMission, activityRecord) {
  const recentActivityIds = sessionRecord.data?.recentActivityIds ?? [];
  return {
    currentMissionChanged: JSON.stringify(sessionRecord.data?.currentMission ?? null) !== JSON.stringify(currentMission),
    recentActivityAdded: Boolean(currentMission.activityId && !recentActivityIds.includes(currentMission.activityId)),
    activityRecognized: Boolean(activityRecord)
  };
}

function buildResponse(body, status, details, extra = {}) {
  return {
    schemaVersion: "overlay-mission-sync-response.v1",
    playerId: defaultPlayerId(body),
    status,
    mode: body.mode ?? "snapshot",
    note: status === "preview"
      ? "Local API returned a mission context merge preview. Send writeMode: \"persistent\" and confirmWrite: true to write player session mission state."
      : "Persistent mission context merge completed with a backup written first.",
    mission: details.currentMission,
    activityRecord: details.activityRecord,
    records: {
      session: details.sessionPath
    },
    changes: details.changes,
    ...extra,
    nextActions: status === "preview"
      ? [
          "Review activityId, faction, objective, and modifiers before writing.",
          "Send writeMode: \"persistent\" and confirmWrite: true only when the caller intends to mutate player session state.",
          "Use mission context with loadout state to bias assistant recommendations."
        ]
      : [
          "Rebuild player-aware views if downstream materialized views begin consuming currentMission.",
          "Attach continuous overlay event-feed updates when mission progress changes."
        ]
  };
}

export async function previewOverlayMissionSync(body, options = {}) {
  const playerId = defaultPlayerId(body);
  const shouldWrite = body.writeMode === "persistent" && body.confirmWrite === true;
  const activityRecord = await findActivityRecord(body.mission?.activityId);
  const currentMission = normalizeMission(body, activityRecord);
  const session = await getSessionRecord(playerId);
  const changes = buildChanges(session.record, currentMission, activityRecord);
  const details = {
    currentMission,
    activityRecord,
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
    const error = new Error("Persistent overlay mission sync requires a valid x-warframe-kb-api-key header.");
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

  const existingRecentActivityIds = session.record.data?.recentActivityIds ?? [];
  const recentActivityIds = currentMission.activityId
    ? [currentMission.activityId, ...existingRecentActivityIds.filter((activityId) => activityId !== currentMission.activityId)].slice(0, 10)
    : existingRecentActivityIds;
  const sourceRecord = {
    type: "overlay-api",
    value: body.syncId ?? `overlay-mission-api.${safeNow}`
  };
  const updatedSession = {
    ...session.record,
    updatedAt: now,
    data: {
      ...(session.record.data ?? {}),
      currentMission,
      recentActivityIds
    },
    sources: [
      sourceRecord,
      ...(session.record.sources ?? []).filter((source) => source.type !== "overlay-api")
    ]
  };

  await writeJson(session.path, updatedSession);

  const normalizedPath = `imports/overlay-sync/normalized/local-api-mission-${safeNow}.json`;
  await writeJson(normalizedPath, {
    generatedAt: now,
    playerId,
    source: body.source ?? "local-api",
    snapshotType: body.snapshotType ?? "mission",
    capturedAt: currentMission.capturedAt,
    mission: currentMission,
    activityRecord,
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
