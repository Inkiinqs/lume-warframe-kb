import { runPowerShell } from "../powershell.mjs";
import { getLiveContext } from "./live-context-service.mjs";

const supportedPlayerId = "player.demo-account";

async function runRefreshStep(script, label) {
  const startedAt = Date.now();
  await runPowerShell(script, []);
  return {
    label,
    script,
    durationMs: Date.now() - startedAt
  };
}

export async function refreshLiveContextAfterWrite(playerId, options = {}) {
  if (playerId !== supportedPlayerId) {
    return {
      status: "skipped",
      reason: "assistant-live-context.view.json is currently materialized for player.demo-account only.",
      playerId,
      supportedPlayerId
    };
  }

  try {
    const steps = [];
    if (options.refreshInventoryViews) {
      steps.push(await runRefreshStep("scripts/build-player-views.ps1", "player-owned-summary"));
    }
    if (options.refreshBuildViews) {
      steps.push(await runRefreshStep("scripts/build-player-build-skeletons.ps1", "player-build-skeletons"));
    }
    steps.push(await runRefreshStep("scripts/build-assistant-live-context.ps1", "assistant-live-context"));

    const liveContext = await getLiveContext(playerId);
    return {
      status: "refreshed",
      playerId,
      steps,
      changeToken: liveContext.transport?.changeToken ?? null,
      generatedAt: liveContext.generatedAt ?? null,
      staleSources: liveContext.transport?.staleSources ?? []
    };
  } catch (error) {
    return {
      status: "failed",
      playerId,
      error: error.message
    };
  }
}
