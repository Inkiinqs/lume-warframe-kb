import { readdir } from "node:fs/promises";
import { readJson } from "../json-store.mjs";
import { repoPath } from "../config.mjs";

export function timestamp() {
  return new Date().toISOString();
}

export function safeTimestamp(value) {
  return value.replace(/[:.]/g, "-");
}

export function defaultPlayerId(body) {
  return body.playerId ?? "player.demo-account";
}

export function playerSlug(playerId) {
  return playerId.replace(/^player\./, "");
}

export function sessionPathForPlayer(playerId) {
  return `player/sessions/${playerSlug(playerId)}-session-latest.json`;
}

export async function listJsonRecords(relativeDirectory) {
  const directory = repoPath(...relativeDirectory.split("/"));
  const entries = await readdir(directory, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => `${relativeDirectory}/${entry.name}`);
}

export async function readOptionalJson(relativePath) {
  try {
    return await readJson(relativePath);
  } catch (error) {
    if (error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

export async function getSessionRecord(playerId) {
  const expectedPath = sessionPathForPlayer(playerId);
  const expected = await readOptionalJson(expectedPath);
  if (expected) {
    return { path: expectedPath, record: expected };
  }

  for (const candidatePath of await listJsonRecords("player/sessions")) {
    const candidate = await readJson(candidatePath);
    if (candidate.playerId === playerId && candidate.category === "session") {
      return { path: candidatePath, record: candidate };
    }
  }

  return {
    path: expectedPath,
    record: {
      id: `${playerId}-session-latest`,
      playerId,
      category: "session",
      updatedAt: timestamp(),
      data: {},
      sources: []
    }
  };
}
