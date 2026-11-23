# Offline official-source compiler: no SourceForge, no .paf.exe tool download,
# no installer wizard invocation, no GUI. Requires the COMPLETE, GENERATED
# PortableApps.com Installer NSIS sources for this app (not InstallerWizard.nsi).
param(
  [Parameter(Mandatory)]$Info,
  [Parameter(Mandatory)][string]$Target,
  [Parameter(Mandatory)][string]$Work,
  [string]$OfficialSourceDir='',
  [int]$TimeoutSeconds=600
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/common.ps1"
Require ($IsWindows) 'The official source compiler requires Windows.'
$workDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Work)
$stageParent=Join-Path $workDir 'isolated-source'
$stage=Join-Path $stageParent $Info.Folder
Require (-not (Test-Path -LiteralPath $workDir)) 'Refusing to reuse existing official build work directory. Choose a clean output directory.'
Require (-not (Test-Path -LiteralPath $Target)) 'Refusing to overwrite official output.'
# Identify a generated per-app source tree. The uploaded InstallerWizard.nsi
# is not a substitute for PortableApps.comInstaller.nsi and its dependencies.
$sourceDir=if($OfficialSourceDir) { Resolve-Directory $OfficialSourceDir } else { Join-Path $Info.Source 'Other/Source' }
$entry=Join-Path $sourceDir 'PortableApps.comInstaller.nsi'
$config=Join-Path $sourceDir 'PortableApps.comInstallerConfig.nsh'
Require (Test-Path -LiteralPath $entry -PathType Leaf) @"
OFFICIAL_SOURCE_MISSING: Complete PortableApps.com Installer application template not found:
  $entry
Your uploaded PortableApps_Installer_Source.zip contains InstallerWizard.nsi (GUI packaging wizard),
NOT the installer template and support files it uses. We cannot compile the genuine installer from
that wizard-only ZIP. Provide a complete generated Other/Source folder or set official-source-dir.
No external executable will be downloaded, and custom-nsis builds are unaffected.
"@
Require (Test-Path -LiteralPath $config -PathType Leaf) "OFFICIAL_SOURCE_MISSING: $config is required for direct headless NSIS compilation."
Assert-NoReparse $sourceDir
# If both folders are the same, normal robocopy copies it. If supplied externally,
# overlay only the vetted source files into the isolated staged application.
New-Item -ItemType Directory -Path $stageParent -Force | Out-Null
$rcArgs=@($Info.Source,$stage,'/E','/XJ','/R:1','/W:1','/NP','/NFL','/NDL','/NJH','/NJS','/XD',(Join-Path $Info.Source 'Data'))
& robocopy.exe @rcArgs | Out-Null
Require ($LASTEXITCODE -le 7) "Unable to stage application (robocopy exit $LASTEXITCODE)."
Require (-not (Test-Path -LiteralPath (Join-Path $stage 'Data'))) 'User Data was unexpectedly staged!'
$generatedDir=Join-Path $stage 'Other/Source'
if ($sourceDir.TrimEnd('\') -ine (Join-Path $Info.Source 'Other/Source').TrimEnd('\')) {
  New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null
  & robocopy.exe $sourceDir $generatedDir '/E' '/XJ' '/R:1' '/W:1' '/NP' '/NFL' '/NDL' '/NJH' '/NJS' | Out-Null
  Require ($LASTEXITCODE -le 7) "Unable to stage official NSIS source (robocopy exit $LASTEXITCODE)."
}
$stageEntry=Join-Path $generatedDir 'PortableApps.comInstaller.nsi'
$stageConfig=Join-Path $generatedDir 'PortableApps.comInstallerConfig.nsh'
Require (Test-Path -LiteralPath $stageEntry -PathType Leaf) 'Staged installer source is missing.'
Require (Test-Path -LiteralPath $stageConfig -PathType Leaf) 'Staged official config is missing.'
# The official wizard writes VERSION, DISPLAYVERSION, APPID and PORTABLEAPPNAME.
# Refresh only these known source macros in the isolated copy, so routine app
# version upgrades do not require rebuilding the wrapper or changing pinned URLs.
$values=@{
  'VERSION'=$Info.Version
  'DISPLAYVERSION'=$(if($Info.DisplayVersion){$Info.DisplayVersion}else{$Info.Version})
  'APPID'=$Info.AppID
  'PORTABLEAPPNAME'=$Info.Name
}
$cfg=[IO.File]::ReadAllText($stageConfig)
foreach($key in @('VERSION','DISPLAYVERSION','APPID','PORTABLEAPPNAME')) {
  $rx='(?m)^\s*!define\s+'+$key+'\s+"([^"\r\n]*)"[ \t]*$'
  $m=[regex]::Match($cfg,$rx)
  Require ($m.Success) "OFFICIAL_SOURCE_INCOMPATIBLE: Missing expected !define $key from generated official config. Do not silently substitute a new format."
  $wanted=[string]$values[$key]
  Require ($wanted -notmatch '[`"\r\n]') "Unsafe value in $key"
  $cfg=$cfg.Substring(0,$m.Index) + ($m.Value.Substring(0,$m.Groups[1].Index-$m.Index)) + $wanted + ($m.Value.Substring($m.Groups[1].Index-$m.Index+$m.Groups[1].Length)) + $cfg.Substring($m.Index+$m.Length)
}
# Respect vendor source encoding (typically UTF-16LE with BOM); prevent
# accidental conversion of Unicode NSIS source into invalid ASCII.
$raw=[IO.File]::ReadAllBytes($stageConfig)
if($raw.Length -ge 2 -and $raw[0] -eq 0xff -and $raw[1] -eq 0xfe) {
  [IO.File]::WriteAllText($stageConfig,$cfg,[Text.UnicodeEncoding]::new($false,$true))
} elseif($raw.Length -ge 2 -and $raw[0] -eq 0xfe -and $raw[1] -eq 0xff) {
  [IO.File]::WriteAllText($stageConfig,$cfg,[Text.UnicodeEncoding]::new($true,$true))
} else {
  [IO.File]::WriteAllText($stageConfig,$cfg,[Text.UTF8Encoding]::new($false))
}
# Never execute InstallerWizard.exe or app's installer; the real executable we
# run is the ordinary NSIS *compiler*, with full logging and timeout.
$maker=Get-Makensis
$log=Join-Path $workDir 'official-makensis.log'
$existing=@(Get-ChildItem -LiteralPath $stageParent -File -Filter '*.paf.exe')
Require ($existing.Count -eq 0) 'A .paf.exe already exists in isolated stage; refusing to mix stale outputs.'
Write-Host "Compiling official PortableApps installer *application source* via makensis.exe (non-interactive)."
Write-Host "Source root: $generatedDir"
Invoke-Program $maker @('/V3',$stageEntry) $TimeoutSeconds $generatedDir $log
$generated=@(Get-ChildItem -LiteralPath $stageParent -File -Filter '*.paf.exe')
Require ($generated.Count -eq 1) "Official source did not produce exactly one installer next to portable folder ($($generated.Count) found); see $log."
Assert-PE $generated[0].FullName
Assert-Archive $generated[0].FullName
$seven=Get-7zip
$list=@(& $seven l -slt $generated[0].FullName)
Require ($LASTEXITCODE -eq 0) 'Could not inspect official output archive.'
Require (($list -join "`n") -match '(?i)App[\\/]AppInfo[\\/]appinfo\.ini') 'Official output is missing appinfo.ini.'
Require (($list -join "`n") -notmatch '(?im)^Path = (?:[^\\/\r\n]+[\\/])?Data[\\/]') 'Official output unexpectedly contains user Data.'
Copy-Item -LiteralPath $generated[0].FullName -Destination $Target -ErrorAction Stop
Write-Host "PASS: compiled official-generated NSIS sources without running a wizard or fetching an installer: $Target"
