<#  Pull the freshly built client artifacts out of the mod-razagath-classes
    module into this repo so a release can be cut.

      overlay/Interface/AddOns/SpellBladeUI/*   <- module client-patch/addon
      patch/patch-enUS-Z.MPQ                    <- module client-patch
      patch/Wow.exe                             <- module client-patch (patched exe)
#>
[CmdletBinding()]
param(
    [string]$Module = "C:\Azerothcore\modules\mod-razagath-classes\client-patch",
    [switch]$IncludeExe
)
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot

Copy-Item "$Module\addon\SpellBladeUI\SpellBladeUI.lua" "$Repo\overlay\Interface\AddOns\SpellBladeUI\SpellBladeUI.lua" -Force
Write-Host "synced SpellBladeUI.lua"

if (Test-Path "$Module\patch-enUS-Z.MPQ") {
    Copy-Item "$Module\patch-enUS-Z.MPQ" "$Repo\patch\patch-enUS-Z.MPQ" -Force
    $m = Get-Item "$Repo\patch\patch-enUS-Z.MPQ"
    Write-Host ("synced patch-enUS-Z.MPQ  ({0:N0} bytes)" -f $m.Length)
} else {
    Write-Warning "no patch-enUS-Z.MPQ in $Module - run the module's build_final.pl first"
}

if ($IncludeExe) {
    $patched = "$Module\Wow.exe.spellblade-patched"
    if (Test-Path $patched) {
        Copy-Item $patched "$Repo\patch\Wow.exe" -Force
        Write-Host "synced patched Wow.exe"
    } else {
        Write-Warning "no Wow.exe.spellblade-patched in $Module"
    }
}
