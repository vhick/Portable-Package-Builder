param([Parameter(Mandatory)][string]$ReleaseTag)
. "$PSScriptRoot/common.ps1"
Require ($ReleaseTag -match '^portable-[A-Za-z0-9._+-]+$') 'Target tag must start portable-'
Require ($env:GITHUB_REPOSITORY -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') 'GITHUB_REPOSITORY is missing'
Require (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) 'GH_TOKEN is missing'
$url="https://api.github.com/repos/$($env:GITHUB_REPOSITORY)/releases/tags/$([uri]::EscapeDataString($ReleaseTag))"
$r=Invoke-WebRequest -Uri $url -Headers @{Authorization="Bearer $env:GH_TOKEN";Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'} -TimeoutSec 30 -SkipHttpErrorCheck
if($r.StatusCode -eq 404){Write-Host "Release $ReleaseTag absent, safe to build"; exit 0}
if($r.StatusCode -eq 200){throw "Release $ReleaseTag already exists. Choose a new release tag; never overwrite assets."}
throw "Release lookup failed with HTTP $($r.StatusCode); not treating an authentication or API failure as absence."
