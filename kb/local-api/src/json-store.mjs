import { copyFile, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { repoPath } from "./config.mjs";

export async function readJson(relativePath) {
  const raw = await readFile(repoPath(...relativePath.split("/")), "utf8");
  return JSON.parse(raw);
}

export async function writeJson(relativePath, value) {
  const fullPath = repoPath(...relativePath.split("/"));
  await mkdir(path.dirname(fullPath), { recursive: true });
  await writeFile(fullPath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export async function copyRepoFile(sourceRelativePath, destinationRelativePath) {
  const sourcePath = repoPath(...sourceRelativePath.split("/"));
  const destinationPath = repoPath(...destinationRelativePath.split("/"));
  await mkdir(path.dirname(destinationPath), { recursive: true });
  await copyFile(sourcePath, destinationPath);
}

export async function fileMeta(relativePath) {
  const fullPath = repoPath(...relativePath.split("/"));
  const info = await stat(fullPath);
  return {
    path: relativePath,
    mtimeMs: Math.trunc(info.mtimeMs),
    size: info.size
  };
}
