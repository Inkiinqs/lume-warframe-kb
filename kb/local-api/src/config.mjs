import { fileURLToPath } from "node:url";
import path from "node:path";

const apiRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export const config = {
  apiRoot,
  repoRoot: path.resolve(apiRoot, ".."),
  host: "127.0.0.1",
  port: Number.parseInt(process.env.WARFRAME_KB_API_PORT ?? "4477", 10),
  apiKey: process.env.WARFRAME_KB_API_KEY ?? "dev-local-key"
};

export function repoPath(...parts) {
  return path.join(config.repoRoot, ...parts);
}
