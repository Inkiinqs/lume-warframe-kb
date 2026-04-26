import { copyRepoFile, readJson, writeJson } from "../json-store.mjs";
import { defaultPlayerId, getSessionRecord, listJsonRecords, playerSlug, readOptionalJson, safeTimestamp, timestamp } from "./session-service.mjs";
import { refreshLiveContextAfterWrite } from "./live-context-refresh-service.mjs";

async function getBuildRecord(playerId, body, equipped) {
  const requestedPath = body.buildTemplatePath;
  if (requestedPath) {
    const requested = await readJson(requestedPath);
    return { path: requestedPath, record: requested };
  }

  const requestedId = body.buildTemplateId;
  const candidates = [];
  for (const candidatePath of await listJsonRecords("player/build-templates")) {
    const candidate = await readJson(candidatePath);
    if (candidate.playerId !== playerId || candidate.category !== "build") {
      continue;
    }
    candidates.push({ path: candidatePath, record: candidate });
    if (requestedId && candidate.id === requestedId) {
      return { path: candidatePath, record: candidate };
    }
  }

  const matching = candidates.find(({ record }) => {
    const frameMatches = !equipped.warframeId || record.data?.frameId === equipped.warframeId;
    const weaponMatches = equipped.weaponIds.length === 0 || equipped.weaponIds.some((weaponId) => (record.data?.weaponIds ?? []).includes(weaponId));
    return frameMatches && weaponMatches;
  });
  if (matching) {
    return matching;
  }

  const slug = playerSlug(playerId);
  const frameSlug = (equipped.warframeId ?? "current-loadout").replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "").toLowerCase();
  return {
    path: `player/build-templates/${slug}-${frameSlug}-overlay-build.json`,
    record: {
      id: `${playerId}-${frameSlug}-overlay-build`,
      playerId,
      category: "build",
      updatedAt: timestamp(),
      data: {
        name: "Overlay Captured Build",
        frameId: equipped.warframeId ?? null,
        weaponIds: equipped.weaponIds,
        modIds: [],
        goalTags: ["overlay-captured"],
        upgradeState: {}
      },
      sources: []
    }
  };
}

function normalizeEquipped(body) {
  const equipped = body.equipped ?? {};
  const weaponIds = [
    equipped.primaryWeaponId,
    equipped.secondaryWeaponId,
    equipped.meleeWeaponId,
    ...(Array.isArray(equipped.weaponIds) ? equipped.weaponIds : [])
  ].filter(Boolean);

  return {
    warframeId: equipped.warframeId ?? null,
    primaryWeaponId: equipped.primaryWeaponId ?? null,
    secondaryWeaponId: equipped.secondaryWeaponId ?? null,
    meleeWeaponId: equipped.meleeWeaponId ?? null,
    companionId: equipped.companionId ?? null,
    companionWeaponId: equipped.companionWeaponId ?? null,
    weaponIds: Array.from(new Set(weaponIds))
  };
}

function mergeUpgradeState(existing = {}, incoming = {}) {
  return {
    ...existing,
    ...incoming,
    warframes: {
      ...(existing.warframes ?? {}),
      ...(incoming.warframes ?? {})
    },
    weapons: {
      ...(existing.weapons ?? {}),
      ...(incoming.weapons ?? {})
    },
    companions: {
      ...(existing.companions ?? {}),
      ...(incoming.companions ?? {})
    }
  };
}

function buildCurrentLoadout(body, equipped, buildRecord) {
  return {
    capturedAt: body.capturedAt ?? timestamp(),
    source: body.source ?? "local-api",
    snapshotType: body.snapshotType ?? "loadout",
    buildTemplateId: buildRecord.id,
    equipped: {
      warframeId: equipped.warframeId,
      primaryWeaponId: equipped.primaryWeaponId,
      secondaryWeaponId: equipped.secondaryWeaponId,
      meleeWeaponId: equipped.meleeWeaponId,
      companionId: equipped.companionId,
      companionWeaponId: equipped.companionWeaponId
    }
  };
}

function buildResponse(body, status, details, extra = {}) {
  return {
    schemaVersion: "overlay-loadout-sync-response.v1",
    playerId: defaultPlayerId(body),
    status,
    mode: body.mode ?? "snapshot",
    note: status === "preview"
      ? "Local API returned a loadout merge preview. Send writeMode: \"persistent\" and confirmWrite: true to write session/build upgrade state."
      : "Persistent loadout merge completed with backups written first.",
    equipped: details.equipped,
    upgradeState: details.upgradeState,
    records: {
      session: details.sessionPath,
      buildTemplate: details.buildPath
    },
    changes: details.changes,
    ...extra,
    nextActions: status === "preview"
      ? [
          "Review equipped IDs and upgradeState before writing.",
          "Send writeMode: \"persistent\" and confirmWrite: true only when the caller intends to mutate player session/build state.",
          "Rebuild player-aware views after a persistent loadout merge."
        ]
      : [
          "Rebuild player-aware views so build-fit estimates use the captured upgrade state.",
          "Broaden overlay capture next with mission node/faction context when available."
        ]
  };
}

export async function previewOverlayLoadoutSync(body, options = {}) {
  const playerId = defaultPlayerId(body);
  const shouldWrite = body.writeMode === "persistent" && body.confirmWrite === true;
  const equipped = normalizeEquipped(body);
  const upgradeState = body.upgradeState ?? {};
  const session = await getSessionRecord(playerId);
  const build = await getBuildRecord(playerId, body, equipped);
  const currentLoadout = buildCurrentLoadout(body, equipped, build.record);
  const mergedUpgradeState = mergeUpgradeState(build.record.data?.upgradeState, upgradeState);
  const changes = {
    sessionCurrentLoadoutChanged: JSON.stringify(session.record.data?.currentLoadout ?? null) !== JSON.stringify(currentLoadout),
    buildFrameChanged: (build.record.data?.frameId ?? null) !== equipped.warframeId,
    buildWeaponsChanged: JSON.stringify(build.record.data?.weaponIds ?? []) !== JSON.stringify(equipped.weaponIds),
    upgradeStateChanged: JSON.stringify(build.record.data?.upgradeState ?? {}) !== JSON.stringify(mergedUpgradeState)
  };

  const details = {
    equipped,
    upgradeState: mergedUpgradeState,
    sessionPath: session.path,
    buildPath: build.path,
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
    const error = new Error("Persistent overlay loadout sync requires a valid x-warframe-kb-api-key header.");
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
  const sessionBackup = `player/sessions/backups/${session.record.id}.${safeNow}.json`;
  const buildBackup = `player/build-templates/backups/${build.record.id}.${safeNow}.json`;

  const existingSession = await readOptionalJson(session.path);
  const existingBuild = await readOptionalJson(build.path);
  if (existingSession) {
    await copyRepoFile(session.path, sessionBackup);
  }
  if (existingBuild) {
    await copyRepoFile(build.path, buildBackup);
  }

  const sourceRecord = {
    type: "overlay-api",
    value: body.syncId ?? `overlay-loadout-api.${safeNow}`
  };

  const updatedSession = {
    ...session.record,
    updatedAt: now,
    data: {
      ...(session.record.data ?? {}),
      currentLoadout
    },
    sources: [
      sourceRecord,
      ...(session.record.sources ?? []).filter((source) => source.type !== "overlay-api")
    ]
  };

  const updatedBuild = {
    ...build.record,
    updatedAt: now,
    data: {
      ...(build.record.data ?? {}),
      frameId: equipped.warframeId ?? build.record.data?.frameId ?? null,
      weaponIds: equipped.weaponIds.length > 0 ? equipped.weaponIds : (build.record.data?.weaponIds ?? []),
      upgradeState: mergedUpgradeState
    },
    sources: [
      sourceRecord,
      ...(build.record.sources ?? []).filter((source) => source.type !== "overlay-api")
    ]
  };

  await writeJson(session.path, updatedSession);
  await writeJson(build.path, updatedBuild);

  const normalizedPath = `imports/overlay-sync/normalized/local-api-loadout-${safeNow}.json`;
  await writeJson(normalizedPath, {
    generatedAt: now,
    playerId,
    source: body.source ?? "local-api",
    snapshotType: body.snapshotType ?? "loadout",
    capturedAt: currentLoadout.capturedAt,
    equipped,
    upgradeState: mergedUpgradeState,
    records: {
      session: session.path,
      buildTemplate: build.path
    }
  });

  const liveContextRefresh = await refreshLiveContextAfterWrite(playerId, {
    refreshBuildViews: true
  });

  return buildResponse(body, "merged", details, {
    backupRecords: {
      session: existingSession ? sessionBackup : null,
      buildTemplate: existingBuild ? buildBackup : null
    },
    normalizedOutput: normalizedPath,
    liveContextRefresh
  });
}
