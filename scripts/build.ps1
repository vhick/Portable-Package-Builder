param(
  [Parameter(Mandatory)][string]$SourceDir,
  [Parameter(Mandatory)][string]$OutputDir,
  [ValidateSet('custom-nsis','official')][string]$Engine='custom-nsis',
  [string]$RunningExe='',
  [string]$OfficialUrl='',
  [string]$OfficialSha256='',
  [int]$TimeoutSeconds=900,
  [string]$PackageRevision='r1'
)
. "$PSScriptRoot/common.ps1"
Require ($IsWindows) 'Packaging requires a Windows runner'
Require ($TimeoutSeconds -ge 60 -and $TimeoutSeconds -le 3600) 'TimeoutSeconds must be 60..3600'
Require ($PackageRevision -match '^[A-Za-z0-9_.-]+$') 'Invalid package revision'
if($RunningExe) { Require (Test-RelativeEXE $RunningExe) 'running-exe must be a relative Windows .exe file inside the portable folder' }
$meta=Get-PackageInfo $SourceDir
New-Item -ItemType Directory -Path $OutputDir -Force|Out-Null
$output=(Get-Item -LiteralPath $OutputDir).FullName
Require (-not $output.StartsWith($meta.Source.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'OutputDir must be outside portable source folder'
Require ($output -ine $meta.Source) 'OutputDir cannot be the source folder' 
$basename="$($meta.Folder)_$($meta.Version)_$Engine-$PackageRevision.paf.exe"
$target=Join-Path $output $basename
Require (-not (Test-Path -LiteralPath $target)) "Refusing to overwrite existing output: $target"
Write-Host "Package input: $($meta.Source); appid: $($meta.AppID); version: $($meta.Version); engine: $Engine"
$work=Join-Path $output '_upb_work'
New-Item -Path $work -ItemType Directory -Force|Out-Null
if($Engine -eq 'custom-nsis') {
  $maker=Get-Makensis
  $nsis=Join-Path $PSScriptRoot '../nsis/community-installer.nsi'
  $args=@('/V3',"/DSOURCE_DIR=$($meta.Source)","/DOUTPUT_PATH=$target","/DAPP_FOLDER=$($meta.Folder)","/DAPP_ID=$($meta.AppID)","/DAPP_NAME=$($meta.Name)","/DLAUNCHER_FILE=$($meta.Launcher)","/DAPP_VERSION=$($meta.Version)","/DRUNNING_EXE=$RunningExe",$nsis)
  Invoke-Program $maker $args $TimeoutSeconds $work (Join-Path $work 'makensis.log')
} else {
  & "$PSScriptRoot/build-official.ps1" -Info $meta -Target $target -Work $work -ToolUrl $OfficialUrl -ExpectedSha $OfficialSha256 -TimeoutSeconds $TimeoutSeconds
}
Assert-PE $target
Assert-Archive $target
$hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $basename"|Set-Content -LiteralPath "$target.sha256" -Encoding ascii
# Provide machine-readable info for downstream steps. Not published inside installer.
[pscustomobject]@{app_id=$meta.AppID;folder=$meta.Folder;version=$meta.Version;engine=$Engine;file=$target;sha256=$hash;provenance= $(if($Engine -eq 'official'){'official-tool'}else{'independent-nsis'})} |
  ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$target.json" -Encoding utf8
if($env:GITHUB_OUTPUT) {
  @("installer-file=$target","installer-sha256=$hash","app-id=$($meta.AppID)","app-version=$($meta.Version)") | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
}
Write-Host "VALIDATED INSTALLER: $target ($hash)"
