param([Parameter(Mandatory)][string]$SourceTag,[Parameter(Mandatory)][string]$AssetName,[Parameter(Mandatory)][string]$Destination)
. "$PSScriptRoot/common.ps1"
Require ($SourceTag -match '^[A-Za-z0-9._+-]+$') 'Invalid source release tag'
Require ($AssetName -match '^[A-Za-z0-9._+-]+\.zip$') 'source-asset must be an explicit ZIP filename, not a glob'
Require ($env:GITHUB_REPOSITORY -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') 'GITHUB_REPOSITORY missing'
$destinationPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
New-Item -ItemType Directory -Path $destinationPath -Force|Out-Null
$asset=Join-Path $destinationPath $AssetName
$checksums=Join-Path $destinationPath 'SHA256SUMS.txt'
$log=Join-Path $destinationPath 'gh-download.log'
Invoke-Program 'gh.exe' @('release','download',$SourceTag,'--repo',$env:GITHUB_REPOSITORY,'--pattern',$AssetName,'--pattern','SHA256SUMS.txt','--dir',$destinationPath,'--clobber') 480 $destinationPath $log
Require (Test-Path -LiteralPath $asset -PathType Leaf) "Missing release asset: $AssetName"
Require (Test-Path -LiteralPath $checksums -PathType Leaf) 'Missing SHA256SUMS.txt; refusing unchecked release download'
$expected=@(Get-Content -LiteralPath $checksums | ForEach-Object {
  if($_ -match '^\s*(?<hash>[A-Fa-f0-9]{64})\s+\*?(?<filename>[^\s]+)\s*$' -and $Matches.filename -eq $AssetName) { $Matches.hash.ToLowerInvariant() }
})
Require ($expected.Count -eq 1) "Expected one SHA-256 entry for $AssetName, found $($expected.Count)"
$actual=(Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
Require ($actual -eq $expected[0]) "Release ZIP SHA-256 mismatch: $AssetName"
Assert-Archive $asset
$extract=Join-Path $destinationPath 'extracted'
New-Item -ItemType Directory -Path $extract -Force |Out-Null
# .NET ExtractToDirectory rejects entries that would escape the output directory.
[IO.Compression.ZipFile]::ExtractToDirectory($asset,$extract)
$possible=@(Get-ChildItem -LiteralPath $extract -Directory | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'App/AppInfo/appinfo.ini')})
Require ($possible.Count -eq 1) "ZIP must contain exactly one root AppNamePortable folder; got $($possible.Count)"
$meta=Get-PackageInfo $possible[0].FullName
if($env:GITHUB_OUTPUT){ "source-dir=$($meta.Source)" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 }
Write-Host "Verified and extracted $AssetName -> $($meta.Source)"
