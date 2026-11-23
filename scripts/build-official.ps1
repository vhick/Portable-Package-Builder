# Genuine PortableApps.com Installer 3.9.24 template, directly compiled with
# its own vendored NSIS. No SourceForge, no GUI, no wizard EXE, no downloads.
param(
  [Parameter(Mandatory)]$Info,
  [Parameter(Mandatory)][string]$Target,
  [Parameter(Mandatory)][string]$Work,
  [string]$OfficialSourceDir='',
  [int]$TimeoutSeconds=900
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/common.ps1"
Require ($IsWindows) 'Official PortableApps source compiler requires Windows.'
# PortableApps.com Installer 3.9.24 uses a wildcard for root HTML files.
# A missing help.html produced an obscure NSIS File '..\..\*.html' error
# with Rufus. Fail early with an application-specific, actionable message.
# Do not generate generic help here: only the application's builder knows its
# real support links, copyright and launch instructions. Custom NSIS is unaffected.
$helpFile=Join-Path $Info.Source 'help.html'
Require (Test-Path -LiteralPath $helpFile -PathType Leaf) "OFFICIAL_HELP_MISSING: $($Info.Folder) must contain help.html at its ROOT (beside $($Info.Launcher)). Have the application-specific builder create it before invoking the official package engine. Do not put help.html in the shared builder repository."
$helpContent=Get-Content -LiteralPath $helpFile -Raw -ErrorAction Stop
Require (($helpContent -match '(?is)<(?:!doctype\s+html\b|html\b)') -and ($helpContent -match '(?is)<body\b') -and ($helpContent.Length -ge 32)) "OFFICIAL_HELP_INVALID: $helpFile is empty or does not look like a usable HTML help page. Provide application-specific HTML with an HTML document and body."
Write-Host "OFFICIAL_HELP_VALIDATED: $helpFile"
$root=Split-Path $PSScriptRoot -Parent
$vendor=if($OfficialSourceDir) { Resolve-Directory $OfficialSourceDir } else { Join-Path $root 'third_party/portableapps-installer-3.9.24' }
$manifestFile=Join-Path $vendor 'UPSTREAM-MANIFEST.json'
Require (Test-Path -LiteralPath $manifestFile -PathType Leaf) "OFFICIAL_SOURCE_MISSING: Vendor manifest absent at $manifestFile. Supply complete extracted vendor source with a verified manifest."
$manifest=Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
Require ($manifest.upstream_version -eq '3.9.24.0') "OFFICIAL_SOURCE_INCOMPATIBLE: Expected reviewed 3.9.24.0 source, got $($manifest.upstream_version). Upgrade upstream only after source audit and tests."
$installerDir=Join-Path $vendor 'App/installer'
$vendorEntry=Join-Path $installerDir 'PortableApps.comInstaller.nsi'
$vendorConfig=Join-Path $installerDir 'PortableApps.comInstallerConfig.nsh'
$maker=Join-Path $vendor 'App/nsis/makensis.exe'
foreach($file in @($vendorEntry,$vendorConfig,$maker)) { Require (Test-Path -LiteralPath $file -PathType Leaf) "OFFICIAL_SOURCE_MISSING: $file" }
Assert-NoReparse $vendor
foreach($property in $manifest.critical_files.PSObject.Properties) {
  $path=Join-Path $vendor $property.Name
  Require (Test-Path -LiteralPath $path -PathType Leaf) "OFFICIAL_SOURCE_MISSING: $path"
  $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
  Require ($hash -eq [string]$property.Value) "OFFICIAL_SOURCE_TAMPERED: $($property.Name) SHA-256 mismatch."
}
$sourceText=[IO.File]::ReadAllText($vendorEntry)
Require ($sourceText -match '!define PORTABLEAPPSINSTALLERVERSION "3\.9\.24\.0"') 'OFFICIAL_SOURCE_INCOMPATIBLE: Source version declaration changed unexpectedly.'
# Do not touch original source (or Data). Compile only an isolated snapshot.
$workDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Work)
Require (-not (Test-Path -LiteralPath $workDir)) 'Refusing to reuse official work folder; prevents stale artifacts.'
Require (-not (Test-Path -LiteralPath $Target)) 'Refusing to overwrite an existing installer.'
$stageParent=Join-Path $workDir 'isolated-source'
$stage=Join-Path $stageParent $Info.Folder
New-Item -ItemType Directory -Path $stageParent -Force | Out-Null
$args=@($Info.Source,$stage,'/E','/XJ','/R:1','/W:1','/NP','/NFL','/NDL','/NJH','/NJS','/XD',(Join-Path $Info.Source 'Data'))
& robocopy.exe @args | Out-Null
Require ($LASTEXITCODE -le 7) "Unable to stage application (robocopy exit $LASTEXITCODE)."
Require (-not (Test-Path -LiteralPath (Join-Path $stage 'Data'))) 'User Data unexpectedly staged!'
Require (Test-Path -LiteralPath (Join-Path $stage 'help.html') -PathType Leaf) 'OFFICIAL_HELP_MISSING: Valid help.html was not copied to the isolated official installer stage.'
$generated=Join-Path $stage 'Other/Source'
New-Item -ItemType Directory -Path $generated -Force | Out-Null
# Vendor does the same upstream source copy before GUI-created config writing.
& robocopy.exe $installerDir $generated '/E' '/XJ' '/R:1' '/W:1' '/NP' '/NFL' '/NDL' '/NJH' '/NJS' | Out-Null
Require ($LASTEXITCODE -le 7) "Unable to stage vendor installer NSIS source (robocopy exit $LASTEXITCODE)."
# The wizard copies these header images separately from App/default_bits;
# they are NOT inside App/installer. Copy them as-is before compiling.
foreach($file in @('PortableApps.comInstallerHeader.bmp','PortableApps.comInstallerHeaderRTL.bmp')) {
  $upstream=Join-Path (Join-Path $vendor 'App/default_bits') $file
  Require (Test-Path -LiteralPath $upstream -PathType Leaf) "OFFICIAL_SOURCE_MISSING: $upstream"
  Copy-Item -LiteralPath $upstream -Destination (Join-Path $generated $file) -Force
}
$copyReadme=Join-Path $vendor 'App/Readme.txt'
$stageReadme=Join-Path $stage 'App/Readme.txt'
if(Test-Path -LiteralPath $copyReadme) { Copy-Item -LiteralPath $copyReadme -Destination $stageReadme -Force }
$vendorLog=Join-Path $stage 'App/AppInfo/pac_installer_log.ini'
if(Test-Path -LiteralPath $vendorLog) { Remove-Item -LiteralPath $vendorLog -Force }
$generator=Join-Path $PSScriptRoot 'generate-official-config.py'
$python=Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
Require ($null -ne $python) 'Python 3 is required to generate official NSIS config (preinstalled on GitHub hosted Windows runners).'
$log=Join-Path $workDir 'official-generate-config.log'
Invoke-Program $python.Source @($generator,'--app',$stage,'--template-dir',$installerDir,'--dest',(Join-Path $generated 'PortableApps.comInstallerConfig.nsh')) 60 $generated $log
# The official template chooses the filename from the generated config; do not
# predict it, and require EXACTLY one new PAF output for this compilation.
$before=@(Get-ChildItem -LiteralPath $stageParent -File -Filter '*.paf.exe')
Require ($before.Count -eq 0) 'Stale official output already exists in isolated source stage.'
$entry=Join-Path $generated 'PortableApps.comInstaller.nsi'
$compileLog=Join-Path $workDir 'official-makensis.log'
Write-Host "Compiling unchanged official PortableApps.com Installer source using bundled NSIS 3.9.24 toolchain (no wizard)."
Invoke-Program $maker @('/V3',$entry) $TimeoutSeconds $generated $compileLog
$built=@(Get-ChildItem -LiteralPath $stageParent -File -Filter '*.paf.exe')
Require ($built.Count -eq 1) "Official compiler did not output exactly one PAF installer ($($built.Count)); see $compileLog."
Assert-PE $built[0].FullName
Assert-Archive $built[0].FullName
$seven=Get-7zip
$entries=@(& $seven l -slt $built[0].FullName)
Require ($LASTEXITCODE -eq 0) 'Unable to inspect official archive contents.'
$list=$entries -join "`n"
Require ($list -match '(?i)App[\\/]AppInfo[\\/]appinfo\.ini') 'Official installer missing appinfo.ini.'
Require ($list -match [regex]::Escape($Info.Launcher)) 'Official installer missing the portable root EXE.'
Require ($list -notmatch '(?i)Data[\\/]private[\\/]secret\.txt') 'Official installer unexpectedly contains test Data.'
Copy-Item -LiteralPath $built[0].FullName -Destination $Target -ErrorAction Stop
Write-Host "PASS: Unmodified official PortableApps.com Installer 3.9.24 compiled headlessly: $Target"
