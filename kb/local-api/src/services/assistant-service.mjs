import { runPowerShell } from "../powershell.mjs";

export async function resolveAssistantQuery(body) {
  if (!body.query || typeof body.query !== "string") {
    throw new Error("POST /api/assistant/query requires a string 'query'.");
  }

  const stdout = await runPowerShell("scripts/resolve-assistant-query.ps1", ["-Query", body.query]);
  return JSON.parse(stdout);
}
