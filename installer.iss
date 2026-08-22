[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName=GryChat
AppVersion=1.0.0
AppPublisher=GryChat
DefaultDirName={autopf}\GryChat
DefaultGroupName=GryChat
OutputDir=installer_output
OutputBaseFilename=GryChat-Setup-1.0.0
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
DisableProgramGroupPage=yes
LicenseFile=
SetupIconFile=
UninstallDisplayIcon={app}\grychat.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "C:\Users\PC\GRYCHAT\grychat\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\GryChat"; Filename: "{app}\grychat.exe"
Name: "{group}\{cm:UninstallProgram,GryChat}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\GryChat"; Filename: "{app}\grychat.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\grychat.exe"; Description: "{cm:LaunchProgram,GryChat}"; Flags: nowait postinstall skipifsilent
