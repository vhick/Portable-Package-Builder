# Full offline Windows build test of BOTH independent PAF creation paths.
# No SourceForge, no downloaded builder .paf.exe, no GUI wizard.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../scripts/common.ps1"
Require ($IsWindows) 'Windows required for genuine NSIS build.'
$base=Join-Path $env:RUNNER_TEMP ('upb-official-'+[Guid]::NewGuid().ToString('N').Substring(0,10))
$src=Join-Path $base 'src/FixturePortable'
$out=Join-Path $base 'dist'
New-Item -ItemType Directory -Path (Join-Path $src 'App/AppInfo'),(Join-Path $src 'App/Fixture/1.2.3.4'),(Join-Path $src 'Other/Source'),(Join-Path $src 'Data/private') -Force | Out-Null
Copy-Item -LiteralPath "$env:WINDIR/System32/where.exe" -Destination (Join-Path $src 'FixturePortable.exe')
Copy-Item -LiteralPath "$env:WINDIR/System32/where.exe" -Destination (Join-Path $src 'App/Fixture/app.exe')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixture-icon.ico') -Destination (Join-Path $src 'App/AppInfo/appicon.ico')
@'
[Format]
Type=PortableApps.comFormat
Version=3.9
[Details]
Name=Fixture Portable
AppID=FixturePortable
Publisher=Portable Package Builder CI
Homepage=example.org
Category=Utilities
Description=Fixture
Language=English
[Version]
DisplayVersion=1.2.3
PackageVersion=1.2.3.4
[License]
Shareable=true
OpenSource=false
Freeware=true
CommercialUse=true
[Control]
Start=FixturePortable.exe
'@ | Set-Content -LiteralPath (Join-Path $src 'App/AppInfo/appinfo.ini') -Encoding ascii
@'
[MainDirectories]
RemoveAppDirectory=true
RemoveOtherDirectory=true
[DirectoriesToPreserve]
PreserveDirectory1=App\Fixture\UserExtras
[CheckRunning]
CloseEXE=FixturePortable.exe
'@ | Set-Content -LiteralPath (Join-Path $src 'Other/Source/installer.ini') -Encoding ascii
'PRIVATE' | Set-Content -LiteralPath (Join-Path $src 'Data/private/secret.txt')
'<html><body>Test package</body></html>' | Set-Content -LiteralPath (Join-Path $src 'help.html')
'Fixture app test' | Set-Content -LiteralPath (Join-Path $src 'App/Fixture/1.2.3.4/version.txt')
$before=(Get-FileHash -LiteralPath (Join-Path $src 'App/AppInfo/appinfo.ini') -Algorithm SHA256).Hash
$secretBefore=(Get-FileHash -LiteralPath (Join-Path $src 'Data/private/secret.txt') -Algorithm SHA256).Hash
try {
  & "$PSScriptRoot/../scripts/build.ps1" -SourceDir $src -OutputDir $out -Engine both -PackageRevision smoke -TimeoutSeconds 600
  $official=@(Get-ChildItem -LiteralPath $out -File -Filter '*_official-*.paf.exe')
  $custom=@(Get-ChildItem -LiteralPath $out -File -Filter '*_custom-nsis-*.paf.exe')
  Require ($official.Count -eq 1 -and $custom.Count -eq 1) 'Both engines did not produce exactly one installer each.'
  Require ((Get-FileHash -LiteralPath (Join-Path $src 'App/AppInfo/appinfo.ini') -Algorithm SHA256).Hash -eq $before) 'Original appinfo.ini modified.'
  Require ((Get-FileHash -LiteralPath (Join-Path $src 'Data/private/secret.txt') -Algorithm SHA256).Hash -eq $secretBefore) 'Original private Data changed.'
  $seven=Get-7zip
  $list=@(& $seven l -slt $official[0].FullName)
  Require ($LASTEXITCODE -eq 0) 'Cannot list official installer payload.'
  $listing=$list -join "`n"
  Require ($listing -match 'App[\\/]AppInfo[\\/]appinfo.ini') 'Official PAF missing appinfo.ini.'
  Require ($listing -match 'App[\\/]Fixture[\\/]1.2.3.4[\\/]version.txt') 'Official PAF missing app payload.'
  Require ($listing -notmatch 'secret.txt') 'Official PAF included private user Data.'
  $log=Join-Path $out '_upb_work/official/official-makensis.log'
  Require (Test-Path -LiteralPath $log) 'No official NSIS compilation log; guard-only test would be invalid.'
  Write-Host 'PASS: Original vendor 3.9.24 NSIS template compiled headlessly into genuine official PAF.'
  Write-Host 'PASS: Custom NSIS engine still emits a separate PAF.'
  Write-Host 'PASS: Original source and personal Data preserved.'
} finally {
  Write-Host "Smoke-test location: $base"
  if($env:GITHUB_WORKSPACE) {
    $diagnostics=Join-Path $env:GITHUB_WORKSPACE 'official-smoke-diagnostics'
    New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
    Get-ChildItem -LiteralPath $base -Filter '*.log' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $diagnostics ($_.Directory.Parent.Name+'-'+$_.Directory.Name+'-'+$_.Name)) -Force
    }
  }
}
