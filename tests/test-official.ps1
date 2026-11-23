# No-download official source preflight smoke test. A green source-guard test
# is NOT proof the full official engine works without complete NSIS sources.
param([string]$OfficialSourceDir='')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../scripts/common.ps1"
Require ($IsWindows) 'Official source guard test requires Windows.'
$base=Join-Path $env:RUNNER_TEMP ('upb-offline-'+[Guid]::NewGuid().ToString('N').Substring(0,10))
$src=Join-Path $base 'src/FixturePortable'
$out=Join-Path $base 'output'
New-Item -ItemType Directory -Path (Join-Path $src 'App/AppInfo'),(Join-Path $src 'App/Fixture'),(Join-Path $src 'Other/Source'),(Join-Path $src 'Data/private') -Force | Out-Null
Copy-Item -LiteralPath "$env:WINDIR/System32/where.exe" -Destination (Join-Path $src 'FixturePortable.exe')
Copy-Item -LiteralPath "$env:WINDIR/System32/where.exe" -Destination (Join-Path $src 'App/Fixture/fixture.exe')
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
DisplayVersion=1.0.0
PackageVersion=1.0.0.0
[License]
Shareable=true
OpenSource=false
Freeware=true
CommercialUse=true
[Control]
Start=FixturePortable.exe
'@ | Set-Content -LiteralPath (Join-Path $src 'App/AppInfo/appinfo.ini') -Encoding ascii
'PRIVATE' | Set-Content -LiteralPath (Join-Path $src 'Data/private/secret.txt')
$hashBefore=(Get-FileHash -LiteralPath (Join-Path $src 'App/AppInfo/appinfo.ini') -Algorithm SHA256).Hash
try {
  if ($OfficialSourceDir) {
    & "$PSScriptRoot/../scripts/build.ps1" -SourceDir $src -OutputDir $out -Engine both -PackageRevision smoke -OfficialSourceDir $OfficialSourceDir -TimeoutSeconds 600
    $official=@(Get-ChildItem -LiteralPath $out -File -Filter '*_official-*.paf.exe')
    $custom=@(Get-ChildItem -LiteralPath $out -File -Filter '*_custom-nsis-*.paf.exe')
    Require ($official.Count -eq 1 -and $custom.Count -eq 1) 'Dual engine did not produce exactly two outputs.'
    Require (Test-Path -LiteralPath (Join-Path $src 'Data/private/secret.txt')) 'Unexpected modification of original Data.'
    Require ((Get-FileHash -LiteralPath (Join-Path $src 'App/AppInfo/appinfo.ini') -Algorithm SHA256).Hash -eq $hashBefore) 'Modified original appinfo.ini.'
    $seven=Get-7zip
    $listing=@(& $seven l -slt $official[0].FullName)
    Require (($listing -join "`n") -notmatch '(?i)secret\.txt') 'Private user data leaked into official PAF.'
    Write-Host 'PASS: genuine source compilation with user-provided complete generated template.'
  } else {
    & "$PSScriptRoot/../scripts/build.ps1" -SourceDir $src -OutputDir $out -Engine custom-nsis -PackageRevision smoke
    $custom=@(Get-ChildItem -LiteralPath $out -File -Filter '*_custom-nsis-*.paf.exe')
    Require ($custom.Count -eq 1) 'Custom engine regression.'
    $caught=$false
    try {
      & "$PSScriptRoot/../scripts/build.ps1" -SourceDir $src -OutputDir (Join-Path $base 'missing-output') -Engine official -PackageRevision smoke -TimeoutSeconds 60
    } catch {
      if($_.Exception.Message -match 'OFFICIAL_SOURCE_MISSING') { $caught=$true; Write-Host 'PASS: missing official application installer source is rejected without downloads.' }
      else { throw }
    }
    Require ($caught) 'Official engine did not reject missing source.'
    Write-Host 'SOURCE GUARD ONLY. Actual official compilation NOT TESTED: full generated official Other/Source is not provided.'
  }
} finally {
  Write-Host "Diagnostics temp folder: $base"
  if ($env:GITHUB_WORKSPACE) {
    $diagnostics=Join-Path $env:GITHUB_WORKSPACE 'official-smoke-diagnostics'
    New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
    Get-ChildItem -LiteralPath $base -Filter '*.log' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $diagnostics ($_.Directory.Name+'-'+$_.Name)) -Force
    }
  }
}
