param(
  [Parameter(Mandatory)][string]$SourceDir,
  [Parameter(Mandatory)][string]$OutputDir,
  [ValidateSet('custom-nsis','official','both')][string]$Engine='custom-nsis',
  [string]$RunningExe='',
  [string]$OfficialSourceDir='',
  [int]$TimeoutSeconds=900,
  [string]$PackageRevision='r1'
)
. "$PSScriptRoot/common.ps1"
Require ($IsWindows) 'Packaging requires a Windows runner.'
Require ($TimeoutSeconds -ge 60 -and $TimeoutSeconds -le 3600) 'TimeoutSeconds must be 60..3600.'
Require ($PackageRevision -match '^[A-Za-z0-9_.-]+$') 'Invalid package revision.'
if ($RunningExe) { Require (Test-RelativeEXE $RunningExe) 'running-exe must be a relative Windows .exe inside the portable folder.' }
$meta=Get-PackageInfo $SourceDir
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$output=(Get-Item -LiteralPath $OutputDir).FullName
Require (-not $output.StartsWith($meta.Source.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'OutputDir must be outside portable source folder.'
Require ($output -ine $meta.Source) 'OutputDir cannot be the source folder.'
$work=Join-Path $output '_upb_work'
New-Item -Path $work -ItemType Directory -Force | Out-Null
$results=@{}
foreach($chosen in $(if($Engine -eq 'both') { @('custom-nsis','official') } else { @($Engine) })) {
  $basename="$($meta.Folder)_$($meta.Version)_$chosen-$PackageRevision.paf.exe"
  $target=Join-Path $output $basename
  Require (-not (Test-Path -LiteralPath $target)) "Refusing to overwrite existing output: $target"
  Write-Host "Preparing engine=$chosen input=$($meta.Source) appid=$($meta.AppID) version=$($meta.Version)"
  if($chosen -eq 'custom-nsis') {
    $maker=Get-Makensis
    $nsis=Join-Path $PSScriptRoot '../nsis/community-installer.nsi'
    $args=@('/V3',"/DSOURCE_DIR=$($meta.Source)","/DOUTPUT_PATH=$target","/DAPP_FOLDER=$($meta.Folder)","/DAPP_ID=$($meta.AppID)","/DAPP_NAME=$($meta.Name)","/DLAUNCHER_FILE=$($meta.Launcher)","/DAPP_VERSION=$($meta.Version)","/DRUNNING_EXE=$RunningExe",$nsis)
    Invoke-Program $maker $args $TimeoutSeconds $work (Join-Path $work 'makensis.log')
  } else {
    # The genuine wizard's automatic compile mode is a separate process with
    # private stage; it never modifies the validated input used by custom NSIS.
    & "$PSScriptRoot/build-official.ps1" -Info $meta -Target $target -Work (Join-Path $work 'official') -OfficialSourceDir $OfficialSourceDir -TimeoutSeconds $TimeoutSeconds
  }
  Assert-PE $target
  Assert-Archive $target
  $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $basename" | Set-Content -LiteralPath "$target.sha256" -Encoding ascii
  [pscustomobject]@{ app_id=$meta.AppID;folder=$meta.Folder;version=$meta.Version;engine=$chosen;file=$target;sha256=$hash;provenance=$(if($chosen -eq 'official'){'official-generated-nsis-source'}else{'independent-nsis'}) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$target.json" -Encoding utf8
  $results[$chosen]=[pscustomobject]@{File=$target;Sha=$hash}
  Write-Host "VALIDATED ($chosen) $target  SHA-256 $hash"
}
$main=$(if($Engine -eq 'official') {$results['official']} else {$results['custom-nsis']})
if($env:GITHUB_OUTPUT) {
  $lines=@("installer-file=$($main.File)","installer-sha256=$($main.Sha)","app-id=$($meta.AppID)","app-version=$($meta.Version)")
  foreach($key in @('custom-nsis','official')) {
    $prefix=$(if($key -eq 'official'){'official'}else{'custom'})
    if($results.ContainsKey($key)) {
      $lines+="$prefix-installer-file=$($results[$key].File)"
      $lines+="$prefix-installer-sha256=$($results[$key].Sha)"
    } else {
      $lines+="$prefix-installer-file="
      $lines+="$prefix-installer-sha256="
    }
  }
  $lines | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8
}
Write-Host "SUCCESS: $Engine engine(s); $($results.Count) separate validated installer(s)."
