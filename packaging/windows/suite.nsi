Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "payload.nsh"
Name "PAPNG Suite"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\PAPNG Suite"
InstallDirRegKey HKCU "Software\TinyGames\PAPNG Suite" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 32
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "PAPNG Suite"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "PAPNG applications installer"
VIAddVersionKey /LANG=1033 "LegalCopyright" "PAPNG contributors"
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION OpenDefaults
!define MUI_FINISHPAGE_RUN_TEXT "Choose Godot PAPNG Viewer as the default for .papng"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Korean"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "Windows x64 is required."
    Abort
  ${EndIf}
  SetRegView 64
  SetShellVarContext current
FunctionEnd

Function OpenDefaults
  ExecShell "open" "ms-settings:defaultapps?registeredAppUser=PAPNG%20Godot%20Viewer"
FunctionEnd

Section "PAPNG applications"
  SetRegView 64
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  !insertmacro InstallPayload
  CreateDirectory "$SMPROGRAMS\PAPNG"
  !insertmacro RegisterApps
  ; Preserve the original class once across upgrades. Never change UserChoice.
  ReadRegStr $0 HKCU "Software\TinyGames\PAPNG Suite" "DefaultSaved"
  ${If} $0 != "yes"
    ReadRegStr $0 HKCU "Software\Classes\.papng" ""
    WriteRegStr HKCU "Software\TinyGames\PAPNG Suite" "PreviousProgID" "$0"
    WriteRegStr HKCU "Software\TinyGames\PAPNG Suite" "DefaultSaved" "yes"
    WriteRegStr HKCU "Software\Classes\.papng" "" "org.tinygames.PapngViewer"
  ${EndIf}
  WriteRegStr HKCU "Software\TinyGames\PAPNG Suite" "InstallDir" "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\PAPNG\Uninstall PAPNG.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\PAPNG\Default apps.lnk" "$WINDIR\explorer.exe" "ms-settings:defaultapps?registeredAppUser=PAPNG%20Godot%20Viewer"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "DisplayName" "PAPNG Suite"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "Publisher" "PAPNG contributors"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite" "NoRepair" 1
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

Section "Uninstall"
  SetRegView 64
  SetShellVarContext current
  ReadRegStr $0 HKCU "Software\Classes\.papng" ""
  ${If} $0 == "org.tinygames.PapngViewer"
    ReadRegStr $1 HKCU "Software\TinyGames\PAPNG Suite" "PreviousProgID"
    ${If} $1 == ""
      DeleteRegValue HKCU "Software\Classes\.papng" ""
    ${Else}
      WriteRegStr HKCU "Software\Classes\.papng" "" "$1"
    ${EndIf}
  ${EndIf}
  !insertmacro UnregisterApps
  Delete "$SMPROGRAMS\PAPNG\Uninstall PAPNG.lnk"
  Delete "$SMPROGRAMS\PAPNG\Default apps.lnk"
  RMDir "$SMPROGRAMS\PAPNG"
  !insertmacro RemovePayload
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\TinyGames\PAPNG Suite"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\PAPNGSuite"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd
