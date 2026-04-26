import { spawn } from "node:child_process";
import { config, repoPath } from "./config.mjs";

export function runPowerShell(scriptRelativePath, args) {
  return new Promise((resolve, reject) => {
    const scriptPath = repoPath(...scriptRelativePath.split("/"));
    const child = spawn(
      "powershell",
      ["-ExecutionPolicy", "Bypass", "-File", scriptPath, "-Root", config.repoRoot, ...args],
      {
        cwd: config.repoRoot,
        windowsHide: true
      }
    );

    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr || stdout || `PowerShell exited with code ${code}`));
        return;
      }
      resolve(stdout);
    });
  });
}
