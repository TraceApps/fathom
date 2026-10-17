; Inno Setup script for Fathom's Windows installer. Built by CI
; (.github/workflows/windows.yml) alongside the existing portable zip, not
; instead of it: some testers want a no-install-needed folder, others want a
; real Start Menu entry and uninstaller. Same build output feeds both.
;
; CI passes the version via /DAppVersion=X.Y.Z; the fallback below only
; matters when compiling this locally (e.g. "iscc fathom.iss" with no define).
#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

#define AppName "Fathom"
#define AppPublisher "TraceApps"
#define AppExeName "fathom.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Fixed GUID so Windows treats every version as the same product (in-place
; upgrades, one Programs-and-Features entry) rather than a new install each time.
AppId={{CA3985E6-779D-4BF1-BB84-96295317CF4D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/TraceApps/fathom
AppSupportURL=https://github.com/TraceApps/fathom/issues
; Per-user (LocalAppData), not Program Files, and no admin prompt: Fathom's
; in-app updater (app_installer.dart) overwrites its own install folder
; directly with no elevation, the same assumption the existing portable zip
; already relies on (it's just extracted wherever the user owns). Program
; Files would need admin rights to write to and silently break that updater
; for anyone who installed this way. VS Code's user installer, Discord and
; Slack all default to this same per-user location for the same reason.
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#AppExeName}
LicenseFile=..\..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=Fathom-Setup-x64
SetupIconFile=..\runner\resources\app_icon.ico
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Everything flutter build windows produces (exe, dll's, data assets), recursed
; as a whole rather than named one by one, so a new bundled DLL (media_kit,
; smtc_windows, etc.) is picked up automatically next build.
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
