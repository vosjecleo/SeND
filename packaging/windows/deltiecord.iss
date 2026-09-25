#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceDir
  #error SourceDir must point to the complete Flutter Windows Release directory
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef OutputBaseName
  #define OutputBaseName "SeND-" + MyAppVersion + "-windows-x64-setup"
#endif

[Setup]
AppId={{2E5E8DB4-F62B-4E91-B4C4-2CA41EDCC91F}
AppName=SeND
AppVersion={#MyAppVersion}
AppPublisher=SeND contributors
AppPublisherURL=https://deltie.net/SeND
AppSupportURL=https://github.com/vosjecleo/SeND/issues
AppUpdatesURL=https://deltie.net/SeND
DefaultDirName={localappdata}\Programs\SeND
UsePreviousAppDir=yes
DefaultGroupName=SeND
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\deltiecord.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany=SeND contributors
VersionInfoDescription=SeND Matrix client installer
VersionInfoCopyright=AGPL-3.0-or-later

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SeND"; Filename: "{app}\deltiecord.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\SeND"; Filename: "{app}\deltiecord.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\deltiecord.exe"; Description: "Launch SeND"; Flags: nowait postinstall skipifsilent

; User sessions and Matrix data live outside {app}. Deliberately do not add
; [UninstallDelete] entries for AppData so upgrades/uninstall preserve them.
