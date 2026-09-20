<#  Pull the freshly built client artifacts out of the mod-razagath-classes
    module into this repo so a release can be cut.

      overlay/Interface/AddOns/SpellBladeUI/SpellBladeUI.lua  <- module client-patch/addon
      patch/patch-enUS-Z.MPQ                                  <- module client-patch

    The game exe is NOT copied here - it is never redistributed. The launcher
    patches the player's own clean Wow.exe in place (see ExePatcher in
    RazagathLauncher.cs). If the five byte offsets ever change, update that table
    and the CleanSha256 / PatchedSha256 constants.
#>
[CmdletBinding()]
param(
    [string]$Module = "C:\Azerothcore\modules\mod-razagath-classes\client-patch"
)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot

Copy-Item "$Module\addon\SpellBladeUI\SpellBladeUI.lua" "$Repo\overlay\Interface\AddOns\SpellBladeUI\SpellBladeUI.lua" -Force
Copy-Item "$Module\addon\SpellBladeUI\SpellBladeUI.toc" "$Repo\overlay\Interface\AddOns\SpellBladeUI\SpellBladeUI.toc" -Force
Write-Host "synced SpellBladeUI"

# MogIt_Razagath - generated custom-item data module for the bundled MogIt.
# (MogIt itself lives directly in overlay/, it is not built from the module.)
$mogitSrc = "$Module\addon\MogIt_Razagath"
$mogitDst = "$Repo\overlay\Interface\AddOns\MogIt_Razagath"
if (Test-Path $mogitSrc) {
    if (Test-Path $mogitDst) { Remove-Item $mogitDst -Recurse -Force }
    Copy-Item $mogitSrc $mogitDst -Recurse -Force
    Write-Host ("synced MogIt_Razagath  ({0} files)" -f (Get-ChildItem $mogitDst -File).Count)
} else {
    Write-Warning "no MogIt_Razagath in $Module - run client-patch/mk_mogit_razagath.pl first"
}

# RazagathMounts - WotLK-native modern-styled mount browser (own addon, not
# an MPQ override - see the module's mk_mount_data.pl for the data source).
$mountsSrc = "$Module\addon\RazagathMounts"
$mountsDst = "$Repo\overlay\Interface\AddOns\RazagathMounts"
if (Test-Path $mountsSrc) {
    if (Test-Path $mountsDst) { Remove-Item $mountsDst -Recurse -Force }
    Copy-Item $mountsSrc $mountsDst -Recurse -Force
    Write-Host ("synced RazagathMounts  ({0} files)" -f (Get-ChildItem $mountsDst -File).Count)
} else {
    Write-Warning "no RazagathMounts in $Module - run client-patch/mk_mount_data.pl first"
}

# RazagathBigBags - raises the client's hardcoded 36-slot bag display cap so
# bigger custom bags render/function correctly, without touching FrameXML
# (see the addon's own header comment for why - this client's anti-tamper
# check aborts on any FrameXML/GlueXML override).
$bagsSrc = "$Module\addon\RazagathBigBags"
$bagsDst = "$Repo\overlay\Interface\AddOns\RazagathBigBags"
if (Test-Path $bagsSrc) {
    if (Test-Path $bagsDst) { Remove-Item $bagsDst -Recurse -Force }
    Copy-Item $bagsSrc $bagsDst -Recurse -Force
    Write-Host ("synced RazagathBigBags  ({0} files)" -f (Get-ChildItem $bagsDst -File).Count)
} else {
    Write-Warning "no RazagathBigBags in $Module"
}

if (Test-Path "$Module\patch-enUS-Z.MPQ") {
    Copy-Item "$Module\patch-enUS-Z.MPQ" "$Repo\patch\patch-enUS-Z.MPQ" -Force
    $m = Get-Item "$Repo\patch\patch-enUS-Z.MPQ"
    Write-Host ("synced patch-enUS-Z.MPQ  ({0:N0} bytes)" -f $m.Length)
} else {
    Write-Warning "no patch-enUS-Z.MPQ in $Module - run the module's build_final.pl first"
}
