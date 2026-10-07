# RazagathWoW

Client launcher, patcher and release tooling for the **RazagathWoW** server
(AzerothCore 3.3.5a, custom *Spellblade* class).

Players run **`RazagathWoW.exe`** — a small launcher that checks
[`manifest.json`](manifest.json) on every start, downloads any changed patch
files from the latest GitHub Release, shows the changelog, and starts the game.

## Download (players)

**[RazagathWoW-Setup.exe](https://github.com/ZeTruNightmare/RazagathWoW/releases/latest/download/RazagathWoW-Setup.exe)**
- always the newest installer (every release carries it under this fixed name).
Run it, point it at an existing 3.3.5a folder to patch it, or let it download the
full client. After that the launcher keeps everything up to date automatically
(the first start downloads the patch files).

### If Windows or your antivirus warns you

The installer and launcher are **not code-signed yet**, which is normal for a new
open-source project, so Windows SmartScreen or an antivirus may warn about them.

- **Blue "Windows protected your PC" screen:** click **More info**, then **Run anyway**.
  Or right-click the downloaded file → **Properties** → tick **Unblock** → OK, then run it.
- **Antivirus "machine learning" / "Trojan:Win32/Wacatac.C!ml" style detections:** these
  are generic guesses, not detections of any specific malware. Every release's installer
  is built automatically by [GitHub Actions](../../actions) from the source in this
  repository, and its SHA-256 is printed on the release page so you can check it with
  PowerShell: `Get-FileHash .\RazagathWoW-Setup.exe`.
- If your antivirus quarantines the file, add the game folder to its exclusions and
  re-run the installer. The launcher only talks to this repository's releases and the
  realm server, and only changes the game's own `Wow.exe` (a backup is kept as
  `Wow.exe.orig`).
- The launcher never asks for, stores or types your password. An optional auto sign-in
  feature existed in launcher 1.6.x; it was removed in 1.7.0 and any saved login it left
  behind is deleted the first time 1.7.0 starts.

## Repo layout

| Path | What |
|---|---|
| `launcher/` | `RazagathLauncher.cs` + `build.ps1` — the launcher (compiled with the Roslyn `csc` from Visual Studio, targets .NET Framework 4.8, no SDK needed) |
| `overlay/` | Files laid onto a base client: the `SpellBladeUI` addon, `WTF/Config.wtf` (windowed by default), `realmlist.wtf` |
| `patch/` | `patch-enUS-Z.MPQ` and the patched `Wow.exe` — **gitignored**, pulled from the module by `tools/sync-from-module.ps1`, distributed as Release assets |
| `tools/` | `sync-from-module.ps1`, `build-release.ps1` (cut a patch), `build-installer.ps1`, `stage-client.ps1` (full-client bundle + publish) |
| `installer/` | `RazagathWoW.nsi` — two-mode installer (patch existing / download full). `tools/` holds `fetch-deps.ps1` + the gitignored `7zr.exe` / `NScurl.dll`. `client-base.nsh` (generated) lists the full-client volumes. |
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

## Building the installer

`RazagathWoW-Setup.exe` has two modes on a page after Welcome:

1. **Patch an existing 3.3.5a client** — point it at the folder, it patches in place.
2. **Download the full client (~15 GB)** — only offered when `installer/client-base.nsh`
   is present. It NScurl-downloads the split volumes (resumable, SHA-256 checked)
   from the `client-base-<ver>` release and extracts them with a bundled `7zr.exe`.

```powershell
pwsh installer/tools/fetch-deps.ps1          # once: grabs 7zr.exe + NScurl.dll (gitignored)
pwsh tools/build-installer.ps1 -Version 2026.09.04
```

To (re)build and publish the full-client bundle, from a **clean** 3.3.5a client:

```powershell
pwsh tools/stage-client.ps1 -Source "D:\ChromieCraft_clean" -Work "D:\rz-stage" `
     -Repo ZeTruNightmare/RazagathWoW -Version 2026.09.04 -Publish
```

That stages + patches + compresses into split `.7z` volumes, publishes the
`client-base-2026.09.04` release, writes `installer/client-base.nsh`, and pushes.
Then re-run `build-installer.ps1` to bundle the new volume list.

## Distribution

- **Patch files** (small): GitHub Releases — the launcher pulls from there each start.
- **Full client** (~15 GB): split `RazagathWoW-client-<ver>.7z.0NN` on the
  `client-base-<ver>` GitHub Release (each < 2 GB). Add a torrent / Cloudflare R2
  mirror later by pointing `CLIENT_BASEURL` in `client-base.nsh` elsewhere.

## What this repo does and doesn't contain

**Contains (all original):** the launcher, `patch-enUS-Z.MPQ` (custom DBC/Lua/BLP),
`SpellBladeUI`, and the build scripts.

**Does not contain any Blizzard binary or asset.** The launcher does not ship a
patched `Wow.exe` — it verifies the SHA-256 of the player's *own* clean 3.3.5a
(build 12340) client, then applies five in-place byte patches (the offset table
lives in `ExePatcher` in `RazagathLauncher.cs`), keeping the original as
`Wow.exe.orig`. What's distributed is a list of five offsets, not Blizzard code.

**The base ~15 GB client** is Blizzard data and is not hosted here. Point players
at an existing 3.3.5a client (e.g. the ChromieCraft client) for the patcher, or
distribute a full bundle via torrent / your own mirror.

## Automated builds

Binaries are built by GitHub Actions on clean Windows runners straight from this
repository's source:

- **Build installer** (`.github/workflows/release-installer.yml`) - runs when a release is
  published, compiles the launcher from `launcher/`, builds the installer with NSIS and
  attaches it to the release as `RazagathWoW-Setup.exe`. It can be re-run manually from
  the Actions tab.
- **Build launcher** (`.github/workflows/build-launcher.yml`) - compiles the launcher on every
  change to `launcher/` to prove the public source builds on its own.

The large game-data archives (`patch-enUS-*.MPQ`) are generated from the server module and
uploaded to the release by `tools/build-release.ps1`; the installer workflow downloads the
patch archive from there.

## License

The launcher, installer, release tooling and the `Razagath` add-on in this repo are
released under the [MIT License](LICENSE). Third-party add-ons bundled under
`overlay/Interface/AddOns/` (Bagnon, MogIt, WDM and their modules) keep their own
original licenses. *World of Warcraft* is a trademark of Blizzard Entertainment;
this project is not affiliated with Blizzard and distributes no Blizzard files.
