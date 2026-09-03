# RazagathWoW

Client launcher, patcher and release tooling for the **RazagathWoW** server
(AzerothCore 3.3.5a, custom *Spellblade* class).

Players run **`RazagathWoW.exe`** — a small launcher that checks
[`manifest.json`](manifest.json) on every start, downloads any changed patch
files from the latest GitHub Release, shows the changelog, and starts the game.

## Repo layout

| Path | What |
|---|---|
| `launcher/` | `RazagathLauncher.cs` + `build.ps1` — the launcher (compiled with the Roslyn `csc` from Visual Studio, targets .NET Framework 4.8, no SDK needed) |
| `overlay/` | Files laid onto a base client: the `SpellBladeUI` addon, `WTF/Config.wtf` (windowed by default), `realmlist.wtf` |
| `patch/` | `patch-enUS-Z.MPQ` and the patched `Wow.exe` — **gitignored**, pulled from the module by `tools/sync-from-module.ps1`, distributed as Release assets |
| `tools/` | `sync-from-module.ps1`, `build-release.ps1` (cut a patch), `stage-client.ps1` (full-client bundle) |
| `installer/` | `RazagathWoW.nsi` — NSIS patcher for players who already own a 3.3.5a client |
| `manifest.json` | Version + file hashes + Release URLs + changelog. The one file the launcher reads. |

## Cutting a patch

After rebuilding `patch-enUS-Z.MPQ` in the module:

```powershell
pwsh tools/build-release.ps1 -Repo <owner>/RazagathWoW `
     -Version 2026.09.05 -Title "Balance pass" `
     -Notes "Spellblade mana costs -10%","Fixed Light Touch tooltip"
```

That rebuilds the launcher, hashes everything, rewrites `manifest.json`,
creates the GitHub Release, uploads assets, and pushes. Players get it on next
launch.

## Building the installers

```powershell
# 1. build the launcher + sync artifacts
pwsh tools/build-release.ps1 -Repo <owner>/RazagathWoW -Version <v> -IncludeExe -DryRun

# 2a. patcher (needs NSIS on PATH)
makensis /DVERSION=<v> /DREALM=logon.example.com /DMANIFEST_URL=https://raw.githubusercontent.com/<owner>/RazagathWoW/main/manifest.json installer/RazagathWoW.nsi

# 2b. full client bundle (split 7z from a clean client)
pwsh tools/stage-client.ps1 -Source "D:\clean-335" -Dest "D:\RazagathWoW" -Zip -ManifestUrl https://raw.githubusercontent.com/<owner>/RazagathWoW/main/manifest.json
```

## Distribution

- **Patch files** (small): GitHub Releases — the launcher pulls from there.
- **Full client** (~15 GB): split `RazagathWoW-client.7z.0NN` as Release assets
  (each < 2 GB), or a mirror (Cloudflare R2 / Internet Archive / torrent).

## Legal note

`Wow.exe` and the base client data are Blizzard-copyrighted. `patch-enUS-Z.MPQ`
and `SpellBladeUI` are original work. Host the base client where you're
comfortable; the small patch pipeline here is all original.
