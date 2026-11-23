# Unmodified PortableApps.com Installer distribution + documented folder-argument
# automatic mode. This builds a PAF with the genuine vendor tool; it does not
# compile or patch the attached InstallerWizard.nsi or replace our custom NSIS.
param(
  [Parameter(Mandatory)]$Info,
  [Parameter(Mandatory)][string]$Target,
  [Parameter(Mandatory)][string]$Work,
  [Parameter(Mandatory)][string]$ToolUrl,
  [Parameter(Mandatory)][string]$ExpectedSha,
  [int]$TimeoutSeconds=600
)
. "$PSScriptRoot/common.ps1"
Require ($ToolUrl -match '^https://(sourceforge\.net|downloads\.sourceforge\.net|[a-z0-9.-]+\.dl\.sourceforge\.net)/') 'Official distribution must use HTTPS on SourceForge (not an unrelated download host).'
Require ($ExpectedSha -match '^[a-fA-F0-9]{64}$') 'Expected SHA-256 must be 64 hex characters.'
$workDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Work)
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$archive=Join-Path $workDir 'PortableApps.comInstaller-vendor.paf.exe'
$toolsDir=Join-Path $workDir 'vendor-tool'
$stageParent=Join-Path $workDir 'isolated-source'
$stage=Join-Path $stageParent $Info.Folder
Require (-not (Test-Path -LiteralPath $stageParent)) 'Official stage already exists; refusing stale output or unexpected source reuse.'
Require (-not (Test-Path -LiteralPath $Target)) 'Refusing overwrite of official output.'
New-Item -ItemType Directory -Path $toolsDir,$stageParent -Force | Out-Null

# The upstream distribution is deliberately NOT bundled in our repository.
# Pin BOTH the versioned download URL and SourceForge-published checksum.
Write-Host "Downloading unmodified PortableApps.com Installer: $ToolUrl"
Invoke-WebRequest -Uri $ToolUrl -MaximumRedirection 8 -TimeoutSec 240 -OutFile $archive -ErrorAction Stop
Require ((Get-Item -LiteralPath $archive).Length -gt 1000000) 'Vendor distribution download unexpectedly small (possibly an HTML download page).'
Require ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ieq $ExpectedSha) 'Official installer distribution checksum mismatch. Update BOTH URL and SHA from official download page.'
Assert-PE $archive
Assert-Archive $archive
$seven=Get-7zip
& $seven x -y "-o$toolsDir" $archive | Out-Null
Require ($LASTEXITCODE -eq 0) 'Could not unpack the verified PortableApps.com Installer distribution.'
$found=@(Get-ChildItem -LiteralPath $toolsDir -Recurse -File -Filter 'PortableApps.comInstaller.exe' -ErrorAction Stop)
Require ($found.Count -eq 1) "Expected one official packaging wizard executable; found $($found.Count)."
$tool=$found[0].FullName
Assert-PE $tool
# The official .paf.exe is distributed as an NSIS archive. Depending on 7-Zip's
# extraction layout, source can be nested one directory deeper. The correct
# application root has both App/nsis and App/installer next to the wizard EXE.
$toolRoot=Split-Path -Parent $tool
Require (Test-Path -LiteralPath (Join-Path $toolRoot 'App/nsis/makensis.exe') -PathType Leaf) 'Official packaging wizard is missing its bundled App/nsis/makensis.exe; check extraction layout.'
Require (Test-Path -LiteralPath (Join-Path $toolRoot 'App/installer/PortableApps.comInstaller.nsi') -PathType Leaf) 'Official packaging wizard is missing App/installer/PortableApps.comInstaller.nsi.'

# The upstream wizard may copy NSIS sources into Other/Source, alter optional
# sections, remove generated files and write AppInfo. NEVER run it on original
# application data. Robocopy /E preserves even empty directories, /XJ excludes
# junctions. Data contains user state and is excluded from distribution.
Assert-NoReparse $Info.Source
$rcArgs=@($Info.Source,$stage,'/E','/XJ','/R:1','/W:1','/NP','/NFL','/NDL','/NJH','/NJS','/XD',(Join-Path $Info.Source 'Data'))
& robocopy.exe @rcArgs | Out-Null
$rc=$LASTEXITCODE
Require ($rc -le 7) "Could not copy application to isolated official stage (robocopy exit $rc)."
Require (Test-Path -LiteralPath (Join-Path $stage 'App/AppInfo/appinfo.ini')) 'Isolated source lost appinfo.ini.'
Require (-not (Test-Path -LiteralPath (Join-Path $stage 'Data'))) 'Data unexpectedly copied into official distribution staging.'

# Source inspection (provided InstallerWizard.nsi v3.9.24) confirms passing one
# quoted folder path activates bolAutomaticCompile and skips folder-selection
# and successful finish pages. DO NOT add /S: that bypasses page callbacks
# needed to set source INI paths; it is NOT a supported compiler switch.
# No one is available to click a modal dialog in GitHub Actions: preflight,
# process timeout, isolated directory and result/log checks are mandatory.
$expectedSource=Join-Path $stage 'App/AppInfo/appinfo.ini'
foreach($pair in @(@('Details','Name'),@('Details','AppID'),@('Version','DisplayVersion'),@('Version','PackageVersion'))) {
  Require (-not [string]::IsNullOrWhiteSpace((Get-IniValue $expectedSource $pair[0] $pair[1]))) "Official wizard requires [$($pair[0])] $($pair[1]) in appinfo.ini; it will not prompt on CI."
}
foreach($key in @('Shareable','OpenSource','Freeware','CommercialUse')) {
  $v=Get-IniValue $expectedSource 'License' $key
  Require ($v -in @('true','false')) "Official builder requires an explicitly truthful [License] $key=true/false. Missing values are not silently invented."
}
$generated=@(Get-ChildItem -LiteralPath $stageParent -File -Filter '*.paf.exe')
Require ($generated.Count -eq 0) 'An output PAF already exists in isolated staging; refusing overwrite.'
$log=Join-Path $workDir 'official-compile.log'
Write-Host 'Running authentic official wizard in automatic (no-click) folder mode on a copy. A progress window may still exist.'
try {
  Invoke-Program $tool @($stage) $TimeoutSeconds $workDir $log
} finally {
  $vendorLog=Join-Path $toolRoot 'Data/PortableApps.comInstallerLog.txt'
  if (Test-Path -LiteralPath $vendorLog) {
    Copy-Item -LiteralPath $vendorLog -Destination (Join-Path $workDir 'vendor-makensis.log') -Force
    Write-Host 'Vendor NSIS compiler log:'
    Get-Content -LiteralPath (Join-Path $workDir 'vendor-makensis.log') -Tail 70 -ErrorAction SilentlyContinue | Out-Host
  }
}
$generated=@(Get-ChildItem -LiteralPath $stageParent -File -Filter '*.paf.exe')
Require ($generated.Count -eq 1) "The official wizard did not produce exactly one installer in isolated stage parent ($($generated.Count) found). Check vendor-makensis.log."
Assert-PE $generated[0].FullName
Assert-Archive $generated[0].FullName
# Verify the EXE has its own PortableApps payload, not just a valid PE header.
$listing=@(& $seven l -slt $generated[0].FullName)
Require ($LASTEXITCODE -eq 0) 'Cannot list generated official installer payload.'
Require (($listing -join "`n") -match '(?i)App[\\/]AppInfo[\\/]appinfo\.ini') 'Official output is missing App/AppInfo/appinfo.ini in archive listing.'
Copy-Item -LiteralPath $generated[0].FullName -Destination $Target -ErrorAction Stop
Write-Host "Official PortableApps.com Installer produced and validated: $Target"
