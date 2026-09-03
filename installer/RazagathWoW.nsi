; RazagathWoW installer
; -----------------------------------------------------------------------------
; A page after Welcome offers two modes:
;
;   1. Patch an existing WoW 3.3.5a (build 12340) client  (e.g. ChromieCraft)
;   2. Download the full RazagathWoW client (~15 GB) and install it here
;
; Both end with: patched Wow.exe (+ Wow.exe.orig backup), patch-enUS-Z.MPQ,
; the SpellBladeUI addon, realmlist.wtf, windowed-by-default config, the
; self-updating RazagathWoW.exe launcher, and shortcuts.
;
; No Blizzard binary is bundled. Mode 1 patches the player's own Wow.exe in
; place. Mode 2 downloads a pre-staged bundle whose Wow.exe was produced the
; same way from a clean client.
;
; Build:
;   pwsh installer\tools\fetch-deps.ps1        # once - grabs 7zr.exe + NScurl.dll
;   makensis /DVERSION=2026.09.04 /DREALM=ztnwow.duckdns.org ^
;            /DMANIFEST_URL=https://raw.githubusercontent.com/ZeTruNightmare/RazagathWoW/main/manifest.json ^
;            installer\RazagathWoW.nsi
;
; installer\client-base.nsh (written by tools\stage-client.ps1) supplies the
; full-client volume list. Absent -> Mode 2 is disabled in that build.
; -----------------------------------------------------------------------------

Unicode true
SetCompressor /SOLID lzma
ManifestDPIAware true

!addplugindir "tools"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "FileFunc.nsh"
!insertmacro GetSize
!insertmacro DriveSpace

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef REALM
  !define REALM "ztnwow.duckdns.org"
!endif
!ifndef MANIFEST_URL
  !define MANIFEST_URL "https://raw.githubusercontent.com/ZeTruNightmare/RazagathWoW/main/manifest.json"
!endif

!if /FileExists "client-base.nsh"
  !define HAVE_CLIENT
  !include "client-base.nsh"
!endif

Name "RazagathWoW ${VERSION}"
OutFile "..\dist\RazagathWoW-Setup-${VERSION}.exe"
InstallDir "C:\Games\World of Warcraft 3.3.5a"
RequestExecutionLevel admin
ShowInstDetails show
BrandingText "RazagathWoW  -  ${REALM}"

Var Mode          ; "patch" | "full"
Var Dlg
Var RbPatch
Var RbFull

; ---- per-volume download block, emitted by client-base.nsh ---------------
!macro DL_VOLUME IDX NAME SHA
  IntOp $R2 ${IDX} + 1
  DetailPrint "Downloading client part $R2 of ${CLIENT_VOLUMES}  (${NAME})"
  NScurl::http GET "${CLIENT_BASEURL}/${NAME}" "$INSTDIR\_dl\${NAME}" \
      /CANCEL /RESUME /INSIST /TIMEOUT 0 /HASH SHA256 "${SHA}" /END
  Pop $0
  ${If} $0 != "OK"
    MessageBox MB_ICONSTOP "Download failed on part $R2 (${NAME}):$\r$\n$0$\r$\n$\r$\nRun Setup again - it resumes where it stopped."
    Abort
  ${EndIf}
!macroend

; =========================================================================
!define MUI_ICON "..\launcher\razagath.ico"
!define MUI_UNICON "..\launcher\razagath.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "RazagathWoW Setup"
!define MUI_WELCOMEPAGE_TEXT "This installs the RazagathWoW client (AzerothCore 3.3.5a, custom Spellblade class).$\r$\n$\r$\nRealm:  ${REALM}$\r$\n$\r$\nNext you'll choose whether to patch a WoW 3.3.5a client you already have, or download the full client."
!insertmacro MUI_PAGE_WELCOME

Page custom ModePage ModePageLeave

!define MUI_PAGE_CUSTOMFUNCTION_PRE DirPreExisting
!define MUI_DIRECTORYPAGE_TEXT_TOP "Select your existing World of Warcraft 3.3.5a folder (build 12340 - the one containing Wow.exe). Your Wow.exe is backed up to Wow.exe.orig; account data and other addons are untouched."
!define MUI_DIRECTORYPAGE_VARIABLE $INSTDIR
!insertmacro MUI_PAGE_DIRECTORY

!define MUI_PAGE_CUSTOMFUNCTION_PRE DirPreFull
!define MUI_DIRECTORYPAGE_TEXT_TOP "Choose an empty folder for the full RazagathWoW client. About 30 GB must be free on the drive during installation (~15 GB afterwards)."
!define MUI_DIRECTORYPAGE_VARIABLE $INSTDIR
!insertmacro MUI_PAGE_DIRECTORY

!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN "$INSTDIR\RazagathWoW.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch RazagathWoW now"
!define MUI_FINISHPAGE_TEXT "RazagathWoW is installed. The launcher finishes updating and starts the game."
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; =========================================================================
Function .onInit
  StrCpy $Mode "patch"
FunctionEnd

Function ModePage
  !insertmacro MUI_HEADER_TEXT "Choose how to install" "Patch a client you already have, or download the full one."
  nsDialogs::Create 1018
  Pop $Dlg
  ${If} $Dlg == error
    Abort
  ${EndIf}

  ${NSD_CreateRadioButton} 0 4u 100% 11u "I already have a World of Warcraft 3.3.5a client  (patch it)"
  Pop $RbPatch
  ${NSD_CreateLabel} 13u 17u 96% 22u "Point Setup at your existing 3.3.5a folder (build 12340, e.g. the ChromieCraft client). Fastest - only the ~50 MB patch is downloaded."

  ${NSD_CreateRadioButton} 0 46u 100% 11u "Download the full RazagathWoW client   (~15 GB)"
  Pop $RbFull
  ${NSD_CreateLabel} 13u 59u 96% 22u "Downloads and installs a complete, ready-to-play client. Needs ~30 GB free during install. The download resumes if interrupted."

  ${If} $Mode == "full"
    ${NSD_Check} $RbFull
  ${Else}
    ${NSD_Check} $RbPatch
  ${EndIf}

  !ifndef HAVE_CLIENT
    EnableWindow $RbFull 0
    ${NSD_CreateLabel} 13u 82u 96% 10u "(The full-client download is not available in this build of Setup.)"
  !endif

  nsDialogs::Show
FunctionEnd

Function ModePageLeave
  ${NSD_GetState} $RbFull $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $Mode "full"
    StrCpy $INSTDIR "C:\Games\RazagathWoW"
  ${Else}
    StrCpy $Mode "patch"
    StrCpy $INSTDIR "C:\Games\World of Warcraft 3.3.5a"
  ${EndIf}
FunctionEnd

Function DirPreExisting
  ${If} $Mode != "patch"
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "Your WoW 3.3.5a folder" "Select the folder that contains Wow.exe."
FunctionEnd

Function DirPreFull
  ${If} $Mode != "full"
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "Install location" "Where to put the full RazagathWoW client."
FunctionEnd

Function .onVerifyInstDir
  ${If} $Mode == "patch"
    IfFileExists "$INSTDIR\Wow.exe" ok
    IfFileExists "$INSTDIR\Wow.exe.orig" ok
      Abort
    ok:
  ${EndIf}
FunctionEnd

; =========================================================================
Section "RazagathWoW" SecMain
  SetDetailsPrint both

  ${If} $Mode == "full"
    Call DownloadFullClient
  ${Else}
    Call CheckExistingClient
  ${EndIf}

  SetOutPath "$INSTDIR"
  DetailPrint "Installing launcher"
  File "..\dist\RazagathWoW.exe"
  FileOpen $0 "$INSTDIR\launcher.cfg" w
  FileWrite $0 '{ "manifestUrl": "${MANIFEST_URL}" }'
  FileClose $0

  SetOutPath "$INSTDIR\Data\enUS"
  DetailPrint "Installing patch-enUS-Z.MPQ"
  File "..\patch\patch-enUS-Z.MPQ"
  SetOutPath "$INSTDIR\Interface\AddOns\SpellBladeUI"
  File "..\overlay\Interface\AddOns\SpellBladeUI\*.lua"
  File "..\overlay\Interface\AddOns\SpellBladeUI\*.toc"

  IfFileExists "$INSTDIR\WTF\Config.wtf" +3 0
    SetOutPath "$INSTDIR\WTF"
    File "..\overlay\WTF\Config.wtf"

  DetailPrint "Setting realmlist -> ${REALM}"
  FileOpen $0 "$INSTDIR\realmlist.wtf" w
  FileWrite $0 "set realmlist ${REALM}$\r$\n"
  FileClose $0
  SetOutPath "$INSTDIR\Data\enUS"
  FileOpen $0 "$INSTDIR\Data\enUS\realmlist.wtf" w
  FileWrite $0 "set realmlist ${REALM}$\r$\n"
  FileClose $0

  DetailPrint "Applying client patches to Wow.exe"
  nsExec::ExecToLog '"$INSTDIR\RazagathWoW.exe" --patch-exe "$INSTDIR"'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_ICONEXCLAMATION "Wow.exe could not be verified as a clean 3.3.5a (build 12340) client.$\r$\nThe launcher will retry on each start."
  ${EndIf}

  RMDir /r "$INSTDIR\Cache"

  CreateShortCut "$DESKTOP\RazagathWoW.lnk" "$INSTDIR\RazagathWoW.exe" "" "$INSTDIR\RazagathWoW.exe" 0
  CreateDirectory "$SMPROGRAMS\RazagathWoW"
  CreateShortCut "$SMPROGRAMS\RazagathWoW\RazagathWoW.lnk" "$INSTDIR\RazagathWoW.exe" "" "$INSTDIR\RazagathWoW.exe" 0
  CreateShortCut "$SMPROGRAMS\RazagathWoW\Uninstall.lnk" "$INSTDIR\RazagathWoW-uninstall.exe"
  WriteUninstaller "$INSTDIR\RazagathWoW-uninstall.exe"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "DisplayName" "RazagathWoW"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "UninstallString" '"$INSTDIR\RazagathWoW-uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "DisplayIcon" "$INSTDIR\RazagathWoW.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "NoRepair" 1

  DetailPrint "Done. Launch RazagathWoW to finish updating and play."
SectionEnd

Function CheckExistingClient
  IfFileExists "$INSTDIR\Wow.exe" haveExe 0
  IfFileExists "$INSTDIR\Wow.exe.orig" haveExe 0
    MessageBox MB_ICONSTOP "No Wow.exe in:$\r$\n$INSTDIR$\r$\n$\r$\nRun Setup again and pick your WoW 3.3.5a folder."
    Abort
  haveExe:
  ${GetSize} "$INSTDIR\Data" "/S=0M" $0 $1 $2
  ${If} $0 < 5000
    MessageBox MB_ICONEXCLAMATION "This folder's Data directory is only $0 MB - it may not be a full WoW client. Continue anyway?" IDYES +2
      Abort
  ${EndIf}
FunctionEnd

Function DownloadFullClient
!ifdef HAVE_CLIENT
  ${DriveSpace} "$INSTDIR\" "/D=F /S=M" $R0
  ${If} $R0 < ${CLIENT_NEED_MB}
    MessageBox MB_ICONSTOP "Not enough free space.$\r$\nNeed about ${CLIENT_NEED_MB} MB free on this drive, have $R0 MB.$\r$\nRun Setup again and choose another location."
    Abort
  ${EndIf}

  InitPluginsDir
  File "/oname=$PLUGINSDIR\7zr.exe" "tools\7zr.exe"
  CreateDirectory "$INSTDIR\_dl"

  !insertmacro DOWNLOAD_CLIENT_VOLUMES

  DetailPrint "Extracting client (a few minutes)..."
  nsExec::ExecToLog '"$PLUGINSDIR\7zr.exe" x "$INSTDIR\_dl\${CLIENT_VOL0}" -o"$INSTDIR" -y'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "Extraction failed (7-Zip exit $0). The download is kept in $INSTDIR\_dl; re-run Setup to retry."
    Abort
  ${EndIf}
  RMDir /r "$INSTDIR\_dl"
!endif
FunctionEnd

; =========================================================================
Section "Uninstall"
  IfFileExists "$INSTDIR\Wow.exe.orig" 0 +3
    Delete "$INSTDIR\Wow.exe"
    Rename "$INSTDIR\Wow.exe.orig" "$INSTDIR\Wow.exe"

  Delete "$INSTDIR\RazagathWoW.exe"
  Delete "$INSTDIR\RazagathWoW.exe.new"
  Delete "$INSTDIR\launcher.cfg"
  Delete "$INSTDIR\Data\enUS\patch-enUS-Z.MPQ"
  RMDir /r "$INSTDIR\Interface\AddOns\SpellBladeUI"
  RMDir /r "$INSTDIR\Cache"
  RMDir /r "$INSTDIR\_dl"
  Delete "$INSTDIR\RazagathWoW-uninstall.exe"
  Delete "$DESKTOP\RazagathWoW.lnk"
  RMDir /r "$SMPROGRAMS\RazagathWoW"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW"
SectionEnd
