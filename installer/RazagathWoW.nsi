; RazagathWoW patcher installer
; -----------------------------------------------------------------------------
; Turns an existing, clean WoW 3.3.5a (build 12340) client into a RazagathWoW
; client: patched game exe, custom MPQ, mandatory addon, windowed-by-default
; config, realmlist, and the self-updating RazagathWoW.exe launcher.
;
; Build:  makensis /DVERSION=2026.09.04 /DREALM=logon.example.com installer\RazagathWoW.nsi
; Inputs it expects (relative to repo root):
;   dist\RazagathWoW.exe
;   patch\Wow.exe                 (patched game binary)
;   patch\patch-enUS-Z.MPQ
;   overlay\Interface\AddOns\SpellBladeUI\*
;   overlay\WTF\Config.wtf
; -----------------------------------------------------------------------------

Unicode true
SetCompressor /SOLID lzma
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef REALM
  !define REALM "CHANGE-ME.razagath.example"
!endif
!ifndef MANIFEST_URL
  !define MANIFEST_URL "https://raw.githubusercontent.com/RAZAGATH_OWNER/RazagathWoW/main/manifest.json"
!endif
!define REPO_ROOT "..\"

Name "RazagathWoW ${VERSION}"
OutFile "..\dist\RazagathWoW-Patcher-${VERSION}.exe"
InstallDir "C:\Games\World of Warcraft 3.3.5a"
RequestExecutionLevel admin
ShowInstDetails show
BrandingText "RazagathWoW"

!define MUI_ICON "..\launcher\razagath.ico"
!define MUI_UNICON "..\launcher\razagath.ico"
!define MUI_WELCOMEPAGE_TITLE "RazagathWoW Patcher"
!define MUI_WELCOMEPAGE_TEXT "This will patch an existing World of Warcraft 3.3.5a (build 12340) client for RazagathWoW.$\r$\n$\r$\nYour original Wow.exe is backed up as Wow.exe.orig. Your account data, screenshots and other addons are left alone.$\r$\n$\r$\nPoint the next screen at your WoW 3.3.5a folder."
!define MUI_DIRECTORYPAGE_TEXT_TOP "Select your World of Warcraft 3.3.5a folder (the one containing Wow.exe)."
!define MUI_FINISHPAGE_RUN "$INSTDIR\RazagathWoW.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch RazagathWoW now"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onVerifyInstDir
  IfFileExists "$INSTDIR\Wow.exe" good
  IfFileExists "$INSTDIR\Wow.exe.orig" good
    Abort
  good:
FunctionEnd

Section "RazagathWoW" SecMain
  SetDetailsPrint both

  ; --- sanity check -----------------------------------------------------
  IfFileExists "$INSTDIR\Wow.exe" +3 0
    MessageBox MB_ICONSTOP "No Wow.exe in:$\r$\n$INSTDIR$\r$\n$\r$\nPick your WoW 3.3.5a folder."
    Abort
  ${GetSize} "$INSTDIR\Data" "/S=0K" $0 $1 $2
  IntCmp $0 1000000 +3 0 +3
    MessageBox MB_ICONEXCLAMATION "This folder doesn't look like a full WoW client (Data folder is tiny). Continue anyway?" IDYES +2
    Abort

  ; --- back up the original exe --------------------------------------
  IfFileExists "$INSTDIR\Wow.exe.orig" skipBackup 0
    DetailPrint "Backing up Wow.exe -> Wow.exe.orig"
    Rename "$INSTDIR\Wow.exe" "$INSTDIR\Wow.exe.orig"
  skipBackup:

  ; --- patched game exe + launcher ---------------------------------
  SetOutPath "$INSTDIR"
  DetailPrint "Installing patched game client"
  File "/oname=Wow.exe" "${REPO_ROOT}patch\Wow.exe"
  File "${REPO_ROOT}dist\RazagathWoW.exe"
  FileOpen $0 "$INSTDIR\launcher.cfg" w
  FileWrite $0 '{ "manifestUrl": "${MANIFEST_URL}" }'
  FileClose $0

  ; --- custom content MPQ -------------------------------------------
  SetOutPath "$INSTDIR\Data\enUS"
  DetailPrint "Installing patch-enUS-Z.MPQ"
  File "${REPO_ROOT}patch\patch-enUS-Z.MPQ"

  ; --- mandatory addon --------------------------------------------
  SetOutPath "$INSTDIR\Interface\AddOns\SpellBladeUI"
  File "${REPO_ROOT}overlay\Interface\AddOns\SpellBladeUI\*.lua"
  File "${REPO_ROOT}overlay\Interface\AddOns\SpellBladeUI\*.toc"

  ; --- windowed-by-default config (only if the player has none) -----
  IfFileExists "$INSTDIR\WTF\Config.wtf" haveCfg 0
    SetOutPath "$INSTDIR\WTF"
    File "${REPO_ROOT}overlay\WTF\Config.wtf"
  haveCfg:

  ; --- realmlist ----------------------------------------------------
  DetailPrint "Setting realmlist -> ${REALM}"
  FileOpen $0 "$INSTDIR\realmlist.wtf" w
  FileWrite $0 "set realmlist ${REALM}$\r$\n"
  FileClose $0
  SetOutPath "$INSTDIR\Data\enUS"
  FileOpen $0 "$INSTDIR\Data\enUS\realmlist.wtf" w
  FileWrite $0 "set realmlist ${REALM}$\r$\n"
  FileClose $0

  ; --- clear cache so new DBC/MPQ is read ------------------------
  RMDir /r "$INSTDIR\Cache"

  ; --- shortcuts + uninstaller -----------------------------------
  CreateShortCut "$DESKTOP\RazagathWoW.lnk" "$INSTDIR\RazagathWoW.exe" "" "$INSTDIR\RazagathWoW.exe" 0
  CreateDirectory "$SMPROGRAMS\RazagathWoW"
  CreateShortCut "$SMPROGRAMS\RazagathWoW\RazagathWoW.lnk" "$INSTDIR\RazagathWoW.exe" "" "$INSTDIR\RazagathWoW.exe" 0
  CreateShortCut "$SMPROGRAMS\RazagathWoW\Uninstall.lnk" "$INSTDIR\RazagathWoW-uninstall.exe"

  WriteUninstaller "$INSTDIR\RazagathWoW-uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "DisplayName" "RazagathWoW"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "UninstallString" '"$INSTDIR\RazagathWoW-uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "DisplayIcon" "$INSTDIR\RazagathWoW.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW" "NoRepair" 1

  DetailPrint "Done. Launch RazagathWoW to finish updating and play."
SectionEnd

Section "Uninstall"
  ; restore the original client exe
  IfFileExists "$INSTDIR\Wow.exe.orig" 0 +3
    Delete "$INSTDIR\Wow.exe"
    Rename "$INSTDIR\Wow.exe.orig" "$INSTDIR\Wow.exe"

  Delete "$INSTDIR\RazagathWoW.exe"
  Delete "$INSTDIR\RazagathWoW.exe.new"
  Delete "$INSTDIR\launcher.cfg"
  Delete "$INSTDIR\Data\enUS\patch-enUS-Z.MPQ"
  RMDir /r "$INSTDIR\Interface\AddOns\SpellBladeUI"
  RMDir /r "$INSTDIR\Cache"
  Delete "$INSTDIR\RazagathWoW-uninstall.exe"

  Delete "$DESKTOP\RazagathWoW.lnk"
  RMDir /r "$SMPROGRAMS\RazagathWoW"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RazagathWoW"
  ; note: realmlist.wtf / Config.wtf are left as-is
SectionEnd
