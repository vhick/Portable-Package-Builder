param([Parameter(Mandatory)]$Info,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$Work,[string]$ToolUrl,[string]$ExpectedSha,[int]$TimeoutSeconds=900)
. "$PSScriptRoot/common.ps1"
Require ($ToolUrl -match '^https://') 'Official tool URL must be HTTPS and supplied by the calling builder'
Require ($ExpectedSha -match '^[a-fA-F0-9]{64}$') 'Official tool SHA-256 must be supplied and verified against vendor publication'
$archive=Join-Path $Work 'official-distribution.paf.exe'
$toolsDir=Join-Path $Work 'official-tool'
New-Item -ItemType Directory -Path $toolsDir -Force|Out-Null
Invoke-WebRequest -Uri $ToolUrl -MaximumRedirection 5 -TimeoutSec 360 -OutFile $archive -ErrorAction Stop
Require ((Get-Item -LiteralPath $archive).Length -gt 1000000) 'Official tool download unexpectedly small'
Require ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ieq $ExpectedSha) 'Official tool SHA256 mismatch'
Assert-PE $archive
$seven=Get-7zip
& $seven x -y "-o$toolsDir" $archive | Out-Host
Require ($LASTEXITCODE -eq 0) 'Official tool extraction failed'
$found=@(Get-ChildItem -LiteralPath $toolsDir -Recurse -File -Filter 'PortableApps.comInstaller.exe')
Require ($found.Count -eq 1) "Expected one authentic installer compiler; found $($found.Count)"
$tool=$found[0].FullName
Assert-PE $tool
$start=Get-Date
# The official executable supports an app-directory argument. Keep bounded: some
# official tool versions may open validation UI even with a command-line argument.
Invoke-Program $tool @($Info.Source) $TimeoutSeconds $Work (Join-Path $Work 'official-compile.log')
$roots=@($Work, (Split-Path $Info.Source -Parent), (Split-Path $Info.Source -Parent | Split-Path -Parent))
$candidates=@(foreach($dir in $roots) { Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.paf.exe' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -ne $archive -and $_.FullName -ne $Target -and $_.LastWriteTime -ge $start.AddSeconds(-10) -and $_.Name -like "$($Info.Folder)*" } }) |
  Sort-Object FullName -Unique
Require ($candidates.Count -eq 1) "Official compiler returned but expected exactly 1 new $($Info.Folder) installer, found $($candidates.Count). Inspect official-compile.log."
Assert-PE $candidates[0].FullName
Copy-Item -LiteralPath $candidates[0].FullName -Destination $Target -ErrorAction Stop
Write-Host "Official tool output discovered: $($candidates[0].FullName)"
