$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/../scripts/common.ps1"
Require ($IsWindows) 'NSIS runtime test requires Windows'
$root=Join-Path $env:RUNNER_TEMP ('upb-fixture-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -Path $root -ItemType Directory -Force |Out-Null
$target=Join-Path $root 'install/FixturePortable'
$foreign=Join-Path $root 'foreign/FixturePortable'
$compiler=Get-Makensis
$nsis=(Resolve-Path "$PSScriptRoot/../nsis/community-installer.nsi").Path
$artifacts=Join-Path $root 'artifacts'
New-Item -Path $artifacts -ItemType Directory|Out-Null
function MakeFixture([string]$ver) {
  $p=Join-Path $root "src-$ver/FixturePortable"
  New-Item -ItemType Directory -Path (Join-Path $p "App/Fixture/$ver"),(Join-Path $p 'App/AppInfo'),(Join-Path $p 'Other') -Force |Out-Null
  Copy-Item "$env:WINDIR/System32/where.exe" (Join-Path $p 'FixturePortable.exe')
  Copy-Item "$PSScriptRoot/fixture-icon.ico" (Join-Path $p 'App/AppInfo/appicon.ico')
  @"
[Format]
Type=PortableApps.comFormat
Version=3.9
[Details]
Name=Fixture Portable
AppID=FixturePortableTest
[Version]
PackageVersion=$ver
DisplayVersion=$ver
[Control]
Start=FixturePortable.exe
"@ | Set-Content -LiteralPath (Join-Path $p 'App/AppInfo/appinfo.ini') -Encoding ascii
  "Version $ver"|Set-Content -LiteralPath (Join-Path $p 'App/Fixture/version.txt')
  "Old version $ver"|Set-Content -LiteralPath (Join-Path $p "App/Fixture/$ver/owned.txt")
  "Support $ver"|Set-Content -LiteralPath (Join-Path $p 'Other/owned.txt')
  return $p
}
function MakeInstaller([string]$source,[string]$label,[bool]$inject=$false) {
  if (-not $inject) {
    # Exercise the real shared action's packaging script (not just makensis).
    $buildOutput=Join-Path $artifacts "build-$label"
    & "$PSScriptRoot/../scripts/build.ps1" -SourceDir $source -OutputDir $buildOutput -Engine custom-nsis -PackageRevision selftest
    $actual=@(Get-ChildItem -LiteralPath $buildOutput -Filter '*.paf.exe' -File)
    Require ($actual.Count -eq 1) "Expected one generated installer for $label"
    return $actual[0].FullName
  }
  $p=Join-Path $artifacts "$label.paf.exe"
  $args=@('/V3',"/DSOURCE_DIR=$source","/DOUTPUT_PATH=$p",'/DAPP_FOLDER=FixturePortable','/DAPP_ID=FixturePortableTest','/DAPP_NAME=Fixture Portable','/DLAUNCHER_FILE=FixturePortable.exe',"/DAPP_VERSION=$label",'/DRUNNING_EXE=App\Fixture\Fixture.exe')
  if($inject){$args+= '/DUPB_TEST_FAIL_AFTER_BACKUP'}
  $args+=$nsis
  Invoke-Program $compiler $args 120 $artifacts (Join-Path $artifacts "$label-compile.log")
  Assert-PE $p
  Assert-Archive $p
  return $p
}
function RunInstaller([string]$exe,[string]$destination,[bool]$expectSuccess) {
  New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force |Out-Null
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$exe
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.ArgumentList.Add('/S')
  $psi.ArgumentList.Add("/D=$destination")
  $p=[Diagnostics.Process]::Start($psi)
  try {
    if(-not $p.WaitForExit(120000)) {try{$p.Kill($true)}catch{};throw "Installer timeout: $exe"}
    if($expectSuccess) { Require ($p.ExitCode -eq 0) "Installer should succeed but exited $($p.ExitCode): $exe" }
    else { Require ($p.ExitCode -ne 0) "Installer should refuse but returned 0: $exe" }
  } finally {$p.Dispose()}
}

try {
  $v1=MakeFixture '1.0.0.0'
  $v2=MakeFixture '2.0.0.0'
  $v3=MakeFixture '3.0.0.0'
  $exe1=MakeInstaller $v1 '1.0.0.0'
  $exe2=MakeInstaller $v2 '2.0.0.0'
  $exeFail=MakeInstaller $v3 '3.0.0.0' $true
  RunInstaller $exe1 $target $true
  Require (Test-Path -LiteralPath (Join-Path $target 'App/Fixture/1.0.0.0/owned.txt')) 'Initial installation missing v1'
  $profile=Join-Path $target 'Data/profile/bookmarks.txt'
  $empty=Join-Path $target 'Data/TraceGuard/empty/inner'
  New-Item -ItemType Directory -Path (Split-Path $profile -Parent),$empty -Force|Out-Null
  'KEEP-ME-UNALTERED' |Set-Content -LiteralPath $profile
  $before=(Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash
  RunInstaller $exe2 $target $true
  Require (-not (Test-Path -LiteralPath (Join-Path $target 'App/Fixture/1.0.0.0'))) 'Old numbered binary directory accumulated'
  Require (Test-Path -LiteralPath (Join-Path $target 'App/Fixture/2.0.0.0/owned.txt')) 'New version not installed'
  Require (Test-Path -LiteralPath $empty -PathType Container) 'Nested empty directory was lost'
  Require ((Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash -eq $before) 'Data was modified by upgrade'
  Require (-not (Test-Path -LiteralPath (Join-Path $target '.__UPB_Backup'))) 'Old App backup was not removed'
  Write-Host 'PASS: v1 -> v2 removes old App versions and preserves Data files and empty directories'
  RunInstaller $exeFail $target $false
  Require (Test-Path -LiteralPath (Join-Path $target 'App/Fixture/2.0.0.0/owned.txt')) 'Failed install did not restore v2 binaries'
  Require (-not (Test-Path -LiteralPath (Join-Path $target 'App/Fixture/3.0.0.0/owned.txt'))) 'Failed install left v3 active'
  Require ((Get-FileHash -LiteralPath $profile -Algorithm SHA256).Hash -eq $before) 'Failed install changed Data'
  Require (-not (Test-Path -LiteralPath (Join-Path $target '.__UPB_Stage'))) 'Rollback left its temporary staging directory'
  Require (-not (Test-Path -LiteralPath (Join-Path $target '.__UPB_Backup'))) 'Rollback left its temporary backup directory'
  Write-Host 'PASS: injected failure rolls back previous application and leaves Data unchanged'
  $foreignApp=Join-Path $foreign 'App/AppInfo'
  New-Item -ItemType Directory -Path $foreignApp -Force|Out-Null
  @('[Details]','AppID=AnotherPortable') |Set-Content -LiteralPath (Join-Path $foreignApp 'appinfo.ini')
  'NO TOUCH'|Set-Content -LiteralPath (Join-Path $foreign 'marker.txt')
  RunInstaller $exe2 $foreign $false
  Require ((Get-Content -LiteralPath (Join-Path $foreign 'marker.txt') -Raw).Trim() -eq 'NO TOUCH') 'Unrelated destination modified'
  Write-Host 'PASS: existing unrelated app rejected'
  $locked=[IO.File]::Open((Join-Path $target 'FixturePortable.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try { RunInstaller $exe2 $target $false } finally {$locked.Dispose()}
  Write-Host 'PASS: locked root launcher aborts upgrade'
  Write-Host 'ALL SYNTHETIC NSIS INSTALL/UPGRADE TESTS PASS'
} finally {
  Write-Host "Fixture location for diagnostics: $root"
}
