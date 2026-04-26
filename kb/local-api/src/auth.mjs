import { config } from "./config.mjs";

export function getSessionContext(req) {
  return {
    apiKey: req.headers["x-warframe-kb-api-key"] ?? "",
    sessionId: req.headers["x-warframe-kb-session-id"] ?? "",
    clientId: req.headers["x-warframe-kb-client-id"] ?? "local-api-client"
  };
}

export function hasWriteAccess(session) {
  return Boolean(session?.apiKey) && session.apiKey === config.apiKey;
}
