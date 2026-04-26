# Lume Warframe KB Publisher

Free public-data pipeline that ships Warframe knowledge-base updates to the
Lume desktop app **without rebuilding the .exe**. Hosted entirely on free
GitHub services (Releases + Actions).

## How it fits together

```
   This repo (public)                              Lume.exe (private app)
   ─────────────────                                ──────────────────
   kb/             ←  data tree                      installWarframeKb()
   version.txt     ←  bump to publish               ↑ on Warframe activation,
   build-kb.mjs    ←  packs zip + manifest          │  fetches manifest.json
   workflow        ←  runs nightly + on push        │  every launch
        ↓                                           │
   GitHub Release v{N}                              │
   ├── warframe-kb-v{N}.zip      ──────────────────►┘  downloads, verifies
   └── manifest.json                                   sha256, swaps in atomically
```

Cost: **$0**. GitHub Releases has unlimited bandwidth on public repos;
GitHub Actions is unlimited on public repos.

## First-time setup

1. **Create a public GitHub repo** named e.g. `lume-warframe-kb`.
2. **Copy the contents of this directory** (`tools/kb-publisher/`) into the
   root of the new repo:
   ```
   build-kb.mjs
   version.txt
   README.md
   .github/workflows/build-kb.yml
   ```
3. **Copy the KB content tree** from your Lume checkout into a `kb/` folder
   at the repo root:
   ```bash
   cp -r resources/companions/warframe/warframe-kb/* /path/to/lume-warframe-kb/kb/
   ```
4. **Push to `main`.** The Action runs automatically and creates Release `v1`
   containing `warframe-kb-v1.zip` and `manifest.json`.
5. **Tell the Lume app where to look** — edit
   `src/companions/warframe/main/plugin.js` and replace
   `REPLACE_WITH_YOUR_GH_USER` in `KB_MANIFEST_URL` with your GitHub
   username/repo. Or set the `LUME_KB_MANIFEST_URL` env var at runtime.
6. **Verify**: launch Lume, open Warframe. The activation status should
   briefly show "Downloading knowledge base v1..." and then "Knowledge base
   v1 installed." A second launch shouldn't re-download (kbVersion match).

## Publishing an update

When DE patches Warframe and you've updated the data in `kb/`:

```bash
# 1. Make your changes inside kb/
# 2. Bump the version
echo "2" > version.txt
git add kb/ version.txt
git commit -m "kb: prime resurgence rotation update"
git push
```

The workflow runs on push, builds `warframe-kb-v2.zip`, creates Release `v2`,
and uploads `manifest.json`. Within minutes every Lume client picks it up on
its next launch.

The nightly cron (`0 3 * * *`) is a safety net — if you forget to push, it
won't republish the same version (it skips when the release already exists).
That same cron slot is where you'd later wire in an automated DE PublicExport
scraper that bumps `version.txt` itself.

## Filling in real data sources

Today `kb/` is a static copy. To make it self-updating from upstream Warframe
data, add a `tools/scrape.mjs` that:

1. Fetches `https://content.warframe.com/PublicExport/index_en.txt.lzma`
   (DE's canonical export — drop tables, items, missions, everything)
2. Pulls supplementary data from `api.warframestat.us` (cleaner schemas)
3. Pulls live prices from `api.warframe.market` (volatile — consider keeping
   this client-side via the local-api server instead)
4. Writes results into `kb/content/items/...`, `kb/ai/materialized-views/...`,
   etc., matching the schema Lume expects (`KB_REQUIRED_FILES` in plugin.js)
5. Bumps `version.txt`

Then add a step to `build-kb.yml` that runs the scraper before
`build-kb.mjs`. The deployment channel below it doesn't change.

## Schema

`manifest.json`:
```json
{
  "schemaVersion": "lume-warframe-kb-manifest.v1",
  "kbVersion": 2,
  "publishedAt": "2026-04-25T03:00:11.482Z",
  "url": "https://github.com/yourname/lume-warframe-kb/releases/download/v2/warframe-kb-v2.zip",
  "sha256": "abc123...",
  "size": 12345678
}
```

The Lume client requires `kbVersion`, `url`, and `sha256`. Anything else is
metadata.

## Troubleshooting

- **Release doesn't appear** — Settings → Actions → General → Workflow
  permissions must be "Read and write".
- **Client doesn't update** — check the Lume console logs for
  `[Lume] KB manifest fetch ...`. Common causes: placeholder URL not replaced,
  firewall blocking github.com, or `kbVersion` not bumped.
- **sha256 mismatch errors** — usually means the Release asset was
  re-uploaded after the manifest was generated. Rerun the workflow.
