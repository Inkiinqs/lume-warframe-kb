import { fileMeta, readJson } from "../json-store.mjs";

const sourceView = "ai/materialized-views/assistant-live-context.view.json";
const sourcePaths = [
  sourceView,
  "player/sessions/demo-account-session-latest.json",
  "ai/materialized-views/player-owned-summary.view.json",
  "ai/materialized-views/player-combat-recommendations.view.json",
  "ai/materialized-views/player-build-skeletons.view.json"
];

async function getLiveContextTransport() {
  const metas = await Promise.all(sourcePaths.map((path) => fileMeta(path)));
  const token = metas
    .map((meta) => `${meta.path}:${meta.mtimeMs}:${meta.size}`)
    .join("|");
  const viewMeta = metas.find((meta) => meta.path === sourceView);
  const staleSources = metas
    .filter((meta) => meta.path !== sourceView && meta.mtimeMs > viewMeta.mtimeMs)
    .map((meta) => meta.path);

  return {
    changeToken: Buffer.from(token).toString("base64url"),
    pollAfterMs: 1000,
    sourceMeta: metas,
    staleSources
  };
}

export async function getLiveContext(playerId) {
  const view = await readJson(sourceView);
  const transport = await getLiveContextTransport();
  if (playerId && view.playerId !== playerId) {
    return {
      schemaVersion: "player-live-context-response.v1",
      playerId,
      sourceView,
      transport,
      warning: `Requested playerId '${playerId}' does not match available live context '${view.playerId}'.`,
      context: null
    };
  }

  return {
    schemaVersion: "player-live-context-response.v1",
    playerId: view.playerId,
    generatedAt: view.generatedAt,
    sourceView,
    transport,
    context: view
  };
}

export async function pollLiveContext(playerId, sinceToken) {
  const transport = await getLiveContextTransport();
  if (sinceToken && sinceToken === transport.changeToken) {
    return {
      schemaVersion: "player-live-context-poll-response.v1",
      playerId,
      status: "not-modified",
      transport,
      context: null
    };
  }

  return {
    schemaVersion: "player-live-context-poll-response.v1",
    playerId,
    status: "modified",
    transport,
    context: await getLiveContext(playerId)
  };
}
