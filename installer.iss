[Setup]
AppId={{D37E77A1-4F2E-4F8A-9A8E-2B8F4C2E9D10}
AppName=HYG Admin Desktop
AppVersion=1.0.2
AppPublisher=HYG Portal
DefaultDirName={autopf}\HYG Admin Desktop
DefaultGroupName=HYG Admin Desktop
OutputDir=installer_output
OutputBaseFilename=HYG_Admin_Desktop_Setup_v1.0.2
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\HYG Admin Desktop"; Filename: "{app}\admin_desktop.exe"
Name: "{autodesktop}\HYG Admin Desktop"; Filename: "{app}\admin_desktop.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\admin_desktop.exe"; Description: "{cm:LaunchProgram,HYG Admin Desktop}"; Flags: nowait postinstall skipifsilent
