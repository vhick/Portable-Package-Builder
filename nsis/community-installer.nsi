; Independent, generic PortableApps-style installer. NOT PortableApps.com Installer.
; Input: validated <PortableFolder> with App, Other and a genuine root launcher.
; No files from Data are embedded; no registry writes and no administrator rights.
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!ifndef SOURCE_DIR
  !error "SOURCE_DIR is required"
!endif
!ifndef OUTPUT_PATH
  !error "OUTPUT_PATH is required"
!endif
!ifndef APP_FOLDER
  !error "APP_FOLDER is required"
!endif
!ifndef APP_ID
  !error "APP_ID is required"
!endif
!ifndef APP_NAME
  !error "APP_NAME is required"
!endif
!ifndef LAUNCHER_FILE
  !error "LAUNCHER_FILE is required"
!endif
!ifndef APP_VERSION
  !error "APP_VERSION is required"
!endif
!ifndef RUNNING_EXE
  !define RUNNING_EXE ""
!endif

Name "${APP_NAME} ${APP_VERSION} (Independent NSIS)"
OutFile "${OUTPUT_PATH}"
InstallDir "$DOCUMENTS\PortableApps\${APP_FOLDER}"
RequestExecutionLevel user
SetCompressor /FINAL zlib
SetDatablockOptimize on
CRCCheck force
SetOverwrite off
ShowInstDetails show
BrandingText "Independent NSIS package - not the official PortableApps.com Installer"
!define MUI_ABORTWARNING
!define MUI_ICON "${SOURCE_DIR}\App\AppInfo\appicon.ico"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Var FailureMessage
Var NewApp
Var NewOther
Var NewLauncher
Var OldApp
Var OldOther
Var OldLauncher
Var FileHandle

Function .onInit
  ; Recognize standard PortableApps Platform layouts alongside installer.
  StrCmp "$INSTDIR" "$DOCUMENTS\PortableApps\${APP_FOLDER}" 0 done_platform
  IfFileExists "$EXEDIR\PortableApps\PortableApps.com\PortableAppsPlatform.exe" 0 +2
    StrCpy $INSTDIR "$EXEDIR\PortableApps\${APP_FOLDER}"
  IfFileExists "$EXEDIR\PortableApps.com\PortableAppsPlatform.exe" 0 +2
    StrCpy $INSTDIR "$EXEDIR\${APP_FOLDER}"
  done_platform:
FunctionEnd

Function Fail
  DetailPrint "ERROR: $FailureMessage"
  IfSilent +2 0
    MessageBox MB_ICONSTOP|MB_OK "$FailureMessage"
  SetErrorLevel 2
  Abort
FunctionEnd

Function CheckNotInUse
  ; An exclusive Windows file open. If it fails, refuse to touch the app.
  Exch $0
  IfFileExists "$0" 0 finished
  System::Call 'kernel32::CreateFileW(w r0, i 0x80000000, i 0, p 0, i 3, i 0, p 0) p .r1'
  StrCmp $1 "-1" locked
  System::Call 'kernel32::CloseHandle(p r1)'
  Goto finished
  locked:
    StrCpy $FailureMessage "A program file is in use or inaccessible: $0. Close the portable app and retry."
    Call Fail
  finished:
  Pop $0
FunctionEnd

Function Preflight
  ; Abort if a previous interrupted transaction exists. NEVER erase its backups.
  IfFileExists "$INSTDIR\.__UPB_Backup" 0 +3
    StrCpy $FailureMessage "An unfinished backup exists. Recover it manually before upgrading: $INSTDIR\.__UPB_Backup"
    Call Fail
  IfFileExists "$INSTDIR\.__UPB_Stage" 0 +3
    StrCpy $FailureMessage "An unfinished stage exists. Inspect it before retrying: $INSTDIR\.__UPB_Stage"
    Call Fail

  IfFileExists "$INSTDIR\App\AppInfo\appinfo.ini" 0 check_new
  ReadINIStr $0 "$INSTDIR\App\AppInfo\appinfo.ini" "Details" "AppID"
  StrCmp $0 "${APP_ID}" verify_locks
  StrCpy $FailureMessage "Existing application AppID ($0) differs from ${APP_ID}; refusing upgrade."
  Call Fail
  check_new:
    IfFileExists "$INSTDIR\*.*" 0 verify_locks
    StrCpy $FailureMessage "Destination contains unknown files or folders; refusing to overwrite."
    Call Fail
  verify_locks:
    ; Reject top-level App/Other directory junctions. Recursively nested reparse
    ; points in old installs still require an application-specific safety audit.
    IfFileExists "$INSTDIR\App" 0 check_other_attributes
      System::Call 'kernel32::GetFileAttributesW(w "$INSTDIR\App") i .r0'
      IntOp $0 $0 & 0x400
      StrCmp $0 "0" check_other_attributes
      StrCpy $FailureMessage "App is a junction or symbolic link. Refusing recursive cleanup."
      Call Fail
    check_other_attributes:
    IfFileExists "$INSTDIR\Other" 0 verify_binary_locks
      System::Call 'kernel32::GetFileAttributesW(w "$INSTDIR\Other") i .r0'
      IntOp $0 $0 & 0x400
      StrCmp $0 "0" verify_binary_locks
      StrCpy $FailureMessage "Other is a junction or symbolic link. Refusing recursive cleanup."
      Call Fail
    verify_binary_locks:
    Push "$INSTDIR\${LAUNCHER_FILE}"
    Call CheckNotInUse
!if "${RUNNING_EXE}" != ""
    Push "$INSTDIR\${RUNNING_EXE}"
    Call CheckNotInUse
!endif
FunctionEnd

; On failed upgrade, restore the previously installed managed files. Data never moves.
Function Rollback
  DetailPrint "Attempting rollback of managed App, Other and launcher. Data untouched."
  SetOutPath "$TEMP"
  StrCmp $NewLauncher "1" 0 +2
    Delete "$INSTDIR\${LAUNCHER_FILE}"
  StrCmp $NewOther "1" 0 +2
    RMDir /r "$INSTDIR\Other"
  StrCmp $NewApp "1" 0 +2
    RMDir /r "$INSTDIR\App"
  StrCmp $OldApp "1" 0 +3
    Rename "$INSTDIR\.__UPB_Backup\App" "$INSTDIR\App"
    IfErrors rollback_problem
  StrCmp $OldOther "1" 0 +3
    Rename "$INSTDIR\.__UPB_Backup\Other" "$INSTDIR\Other"
    IfErrors rollback_problem
  StrCmp $OldLauncher "1" 0 +3
    Rename "$INSTDIR\.__UPB_Backup\${LAUNCHER_FILE}" "$INSTDIR\${LAUNCHER_FILE}"
    IfErrors rollback_problem
  RMDir "$INSTDIR\.__UPB_Backup"
  IfErrors rollback_problem
  ; After rollback, delete our own staged payload so a clean retry is possible.
  ; The verified old application and Data are not modified by this cleanup.
  RMDir /r "$INSTDIR\.__UPB_Stage"
  IfErrors rollback_problem
  DetailPrint "Previous managed application files restored."
  Return
  rollback_problem:
    DetailPrint "ROLLBACK INCOMPLETE: backup left in $INSTDIR\.__UPB_Backup. Do not remove it."
FunctionEnd

Section "Install ${APP_NAME}" SEC_MAIN
  StrCpy $NewApp "0"
  StrCpy $NewOther "0"
  StrCpy $NewLauncher "0"
  StrCpy $OldApp "0"
  StrCpy $OldOther "0"
  StrCpy $OldLauncher "0"
  Call Preflight

  ; Write a new self-contained payload to a reserved directory on the same volume.
  ; No Data files are copied from the builder or overwritten here.
  SetOutPath "$INSTDIR\.__UPB_Stage"
  File /oname=${LAUNCHER_FILE} "${SOURCE_DIR}\${LAUNCHER_FILE}"
  SetOutPath "$INSTDIR\.__UPB_Stage\App"
  File /r "${SOURCE_DIR}\App\*.*"
  SetOutPath "$INSTDIR\.__UPB_Stage\Other"
  File /nonfatal /r "${SOURCE_DIR}\Other\*.*"
  IfErrors stage_error
  IfFileExists "$INSTDIR\.__UPB_Stage\App\AppInfo\appinfo.ini" 0 stage_error
  ReadINIStr $0 "$INSTDIR\.__UPB_Stage\App\AppInfo\appinfo.ini" "Details" "AppID"
  StrCmp $0 "${APP_ID}" 0 stage_error
  IfFileExists "$INSTDIR\.__UPB_Stage\${LAUNCHER_FILE}" 0 stage_error

  CreateDirectory "$INSTDIR\.__UPB_Backup"
  SetOutPath "$TEMP"
  IfFileExists "$INSTDIR\App" 0 old_other
    ClearErrors
    Rename "$INSTDIR\App" "$INSTDIR\.__UPB_Backup\App"
    IfErrors backup_error
    StrCpy $OldApp "1"
  old_other:
  IfFileExists "$INSTDIR\Other" 0 old_launcher
    ClearErrors
    Rename "$INSTDIR\Other" "$INSTDIR\.__UPB_Backup\Other"
    IfErrors backup_error
    StrCpy $OldOther "1"
  old_launcher:
  IfFileExists "$INSTDIR\${LAUNCHER_FILE}" 0 deploy
    ClearErrors
    Rename "$INSTDIR\${LAUNCHER_FILE}" "$INSTDIR\.__UPB_Backup\${LAUNCHER_FILE}"
    IfErrors backup_error
    StrCpy $OldLauncher "1"
  deploy:
  !ifdef UPB_TEST_FAIL_AFTER_BACKUP
    Goto deploy_error
  !endif
  ClearErrors
  Rename "$INSTDIR\.__UPB_Stage\App" "$INSTDIR\App"
  IfErrors deploy_error
  StrCpy $NewApp "1"
  ClearErrors
  Rename "$INSTDIR\.__UPB_Stage\Other" "$INSTDIR\Other"
  IfErrors deploy_error
  StrCpy $NewOther "1"
  ClearErrors
  Rename "$INSTDIR\.__UPB_Stage\${LAUNCHER_FILE}" "$INSTDIR\${LAUNCHER_FILE}"
  IfErrors deploy_error
  StrCpy $NewLauncher "1"
  ; Post-install check. Existing Data and its empty directories are untouched.
  IfFileExists "$INSTDIR\App\AppInfo\appinfo.ini" 0 deploy_error
  IfFileExists "$INSTDIR\${LAUNCHER_FILE}" 0 deploy_error
  ClearErrors
  CreateDirectory "$INSTDIR\Data"
  IfErrors deploy_error
  SetOutPath "$TEMP"
  RMDir "$INSTDIR\.__UPB_Stage"
  ; Backups contain only managed App/Other/launcher, never Data.
  RMDir /r "$INSTDIR\.__UPB_Backup"
  IfErrors cleanup_failed
  DetailPrint "Success. Managed application files updated, old versions removed, Data preserved."
  Goto done
  cleanup_failed:
    DetailPrint "Installation succeeded but backup cleanup failed; backup left for manual inspection."
    Goto done
  stage_error:
    StrCpy $FailureMessage "Could not extract or validate staged application; Data is unchanged."
    Call Fail
  backup_error:
    Call Rollback
    StrCpy $FailureMessage "Could not back up previous application; rollback attempted. Inspect backups if present."
    Call Fail
  deploy_error:
    Call Rollback
    StrCpy $FailureMessage "Could not activate the new application; rollback attempted. Inspect backups if present."
    Call Fail
  done:
SectionEnd
