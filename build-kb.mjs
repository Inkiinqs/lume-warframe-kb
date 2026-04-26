#!/usr/bin/env node
// ─── Warframe KB publisher ───────────────────────────────────────────────────
// Packs the kb/ tree into a versioned zip and writes a manifest.json that
// the Lume client fetches on activation.
//
// Inputs:
//   - kb/                            ← tree of KB content (content/, ai/, local-api/, …)
//   - version.txt                    ← single integer, increases monotonically
//
// Outputs (written to dist/):
//   - warframe-kb-v{N}.zip           ← the bundle
//   - manifest.json                  ← { kbVersion, url, sha256, size, publishedAt }
//
// Env vars:
//   - GITHUB_REPOSITORY              ← e.g. "yourname/lume-warframe-kb" (auto-set by Actions)
//   - KB_RELEASE_BASE_URL (optional) ← override the URL pattern in manifest
//
// Usage:
//   node build-kb.mjs                ← from anywhere; assumes CWD has kb/ + version.txt
// ─────────────────────────────────────────────────────────────────────────────

import { createHash } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { readFileSync, statSync, mkdirSync, writeFileSync, existsSync, rmSync } from 'node:fs'
import path from 'node:path'

const ROOT     = process.cwd()
const KB_DIR   = path.join(ROOT, 'kb')
const VER_FILE = path.join(ROOT, 'version.txt')
const DIST_DIR = path.join(ROOT, 'dist')

if (!existsSync(KB_DIR))    fail(`kb/ directory not found at ${KB_DIR}`)
if (!existsSync(VER_FILE))  fail(`version.txt not found at ${VER_FILE}`)

const kbVersion = parseInt(readFileSync(VER_FILE, 'utf-8').trim(), 10)
if (!Number.isInteger(kbVersion) || kbVersion < 1) {
  fail(`version.txt must contain a positive integer (got: ${readFileSync(VER_FILE, 'utf-8').trim()})`)
}

console.log(`[kb-publisher] Building Warframe KB v${kbVersion}`)

// Reset dist/
rmSync(DIST_DIR, { recursive: true, force: true })
mkdirSync(DIST_DIR, { recursive: true })

const zipName = `warframe-kb-v${kbVersion}.zip`
const zipPath = path.join(DIST_DIR, zipName)

// Pack with the OS `zip` tool — preinstalled on ubuntu-latest GitHub runners,
// also fine on macOS. On Windows use bsdtar bundled with Windows 10+ (resolve
// it explicitly to avoid Git Bash's GNU tar shadowing it in PATH; GNU tar
// reads `C:\path` as an rsync remote spec and dies with "resolve failed").
const isWin = process.platform === 'win32'
const cmd = isWin
  ? { bin: path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'tar.exe'),
      args: ['-a', '-cf', zipPath, '-C', KB_DIR, '.'] }
  : { bin: 'zip', args: ['-r', '-q', zipPath, '.'], cwd: KB_DIR }

const r = spawnSync(cmd.bin, cmd.args, { cwd: cmd.cwd ?? ROOT, stdio: 'inherit' })
if (r.status !== 0) fail(`${cmd.bin} exited with ${r.status}`)

const zipBytes = readFileSync(zipPath)
const sha256   = createHash('sha256').update(zipBytes).digest('hex')
const size     = statSync(zipPath).size

// Build the URL the Lume client will download from. Default points at
// GitHub Releases for the repo this Action is running in.
const repo    = process.env.GITHUB_REPOSITORY || 'REPLACE_WITH_YOUR_GH_USER/lume-warframe-kb'
const baseUrl = process.env.KB_RELEASE_BASE_URL ||
  `https://github.com/${repo}/releases/download/v${kbVersion}`
const url = `${baseUrl}/${zipName}`

const manifest = {
  schemaVersion: 'lume-warframe-kb-manifest.v1',
  kbVersion,
  publishedAt:   new Date().toISOString(),
  url,
  sha256,
  size,
}

writeFileSync(path.join(DIST_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2))
console.log(`[kb-publisher] ✔ ${zipName}  (${(size / 1024 / 1024).toFixed(2)} MB, sha256 ${sha256.slice(0, 12)}…)`)
console.log(`[kb-publisher] ✔ manifest.json points at ${url}`)

function fail(msg) {
  console.error(`[kb-publisher] ✘ ${msg}`)
  process.exit(1)
}
