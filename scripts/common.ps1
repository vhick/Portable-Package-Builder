Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Require([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Resolve-Directory([string]$Value) {
  Require (-not [string]::IsNullOrWhiteSpace($Value)) 'Directory path cannot be empty'
  $p = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Value)
  Require (Test-Path -LiteralPath $p -PathType Container) "Missing directory: $p"
  return (Get-Item -LiteralPath $p).FullName
}
function Get-IniValue([string]$Path,[string]$Section,[string]$Key) {
  $active = $false
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    if ($line -match '^\s*\[([^\]]+)\]\s*$') { $active = ($Matches[1] -ieq $Section); continue }
    if ($active -and $line -match '^\s*([^=;\s]+)\s*=\s*(.*?)\s*$' -and $Matches[1] -ieq $Key) { return $Matches[2].Trim() }
  }
  return ''
}
function Assert-PE([string]$Path) {
  Require (Test-Path -LiteralPath $Path -PathType Leaf) "Missing executable: $Path"
  $f=[IO.File]::OpenRead($Path)
  try {
    Require ($f.Length -gt 128) "Invalid Windows PE size: $Path"
    $r=[IO.BinaryReader]::new($f)
    Require ($r.ReadUInt16() -eq 0x5A4D) "Not an MZ executable: $Path"
    $f.Position=0x3c
    $offset=$r.ReadInt32()
    Require ($offset -ge 64 -and $offset -lt ($f.Length-4)) "PE header missing: $Path"
    $f.Position=$offset
    Require ($r.ReadUInt32() -eq 0x4550) "Not a PE executable: $Path"
  } finally { $f.Dispose() }
}
function Assert-NoReparse([string]$Path) {
  $all=@(Get-Item -LiteralPath $Path -Force) + @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop)
  foreach($item in $all) {
    Require (-not (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) "Reparse point/symlink forbidden in package input: $($item.FullName)"
  }
}
function Test-RelativeEXE([string]$Value) {
  return ($Value -match '^(?!.*(?:^|[\\/])\.\.(?:[\\/]|$))[A-Za-z0-9_.+ -]+(?:\\[A-Za-z0-9_.+ -]+)*\.exe$' -and $Value -notmatch '^\\')
}
function Get-PackageInfo([string]$Source) {
  $source=Resolve-Directory $Source
  $folder=Split-Path $source -Leaf
  Require ($folder -match '^[A-Za-z][A-Za-z0-9_.-]{1,79}$') 'Source folder must be a safe PortableApps folder name'
  $ini=Join-Path $source 'App/AppInfo/appinfo.ini'
  Require (Test-Path -LiteralPath $ini -PathType Leaf) "Missing appinfo.ini: $ini"
  Require (Test-Path -LiteralPath (Join-Path $source 'App') -PathType Container) 'Missing App directory'
  Require (Test-Path -LiteralPath (Join-Path $source 'Other') -PathType Container) 'Missing Other directory (create an empty directory if unused)'
  $id=Get-IniValue $ini 'Details' 'AppID'
  $name=Get-IniValue $ini 'Details' 'Name'
  $version=Get-IniValue $ini 'Version' 'PackageVersion'
  $displayVersion=Get-IniValue $ini 'Version' 'DisplayVersion'
  $format=Get-IniValue $ini 'Format' 'Type'
  $launcher=Get-IniValue $ini 'Control' 'Start'
  Require ($format -eq 'PortableApps.comFormat') 'Incorrect Format.Type (expected PortableApps.comFormat)'
  Require ($id -match '^[A-Za-z0-9_.+-]{2,90}$') 'Unsafe or missing AppID in appinfo.ini'
  Require ($name -match '^[A-Za-z0-9 .()_+\-]{2,120}$') 'Unsafe or missing Name in appinfo.ini'
  Require ($version -match '^\d+\.\d+\.\d+\.\d+$') 'Expected numeric PackageVersion X.Y.Z.W'
  Require ($launcher -match '^[A-Za-z0-9_.-]+\.exe$') 'Control.Start must be a root portable EXE launcher'
  $launcherPath=Join-Path $source $launcher
  Assert-PE $launcherPath
  Require (Test-Path -LiteralPath (Join-Path $source 'App/AppInfo/appicon.ico') -PathType Leaf) 'Missing appicon.ico'
  Assert-NoReparse $source
  return [pscustomobject]@{ Source=$source; Folder=$folder; AppID=$id; Name=$name; Version=$version; DisplayVersion=$displayVersion; Launcher=$launcher }
}
function Get-Makensis {
  $found=Get-Command makensis.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { return $found.Source }
  foreach($p in @("${env:ProgramFiles(x86)}\NSIS\makensis.exe","$env:ProgramFiles\NSIS\makensis.exe","$env:ChocolateyInstall\bin\makensis.exe")) {
    if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
  }
  throw 'makensis.exe not found. Install NSIS (choco install nsis -y --no-progress) on Windows.'
}
function Get-7zip {
  foreach($n in @('7z.exe','7za.exe')) { $cmd=Get-Command $n -ErrorAction SilentlyContinue|Select-Object -First 1; if($cmd){return $cmd.Source} }
  foreach($p in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {if($p -and (Test-Path -LiteralPath $p -PathType Leaf)){return $p}}
  throw '7-Zip executable not available on this Windows runner'
}
function Invoke-Program([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds,[string]$WorkingDirectory,[string]$Log) {
  $startInfo=[Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName=$Executable
  $startInfo.WorkingDirectory=$WorkingDirectory
  $startInfo.UseShellExecute=$false
  $startInfo.CreateNoWindow=$true
  $startInfo.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $startInfo.RedirectStandardOutput=$true
  $startInfo.RedirectStandardError=$true
  foreach($arg in $Arguments) { [void]$startInfo.ArgumentList.Add($arg) }
  $p=[Diagnostics.Process]::new()
  $stdout=$null
  $stderr=$null
  $p.StartInfo=$startInfo
  $lines=[Collections.Generic.List[string]]::new()
  try {
    Require ($p.Start()) "Could not launch $Executable"
    # Drain asynchronously so a full stdout pipe cannot deadlock the child.
    $stdout=$p.StandardOutput.ReadToEndAsync()
    $stderr=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit($TimeoutSeconds*1000)) {
      try{$p.Kill($true)}catch{}
      try{$p.WaitForExit(5000)}catch{}
      throw "Subprocess timed out after $TimeoutSeconds seconds: $Executable"
    }
    [void]$lines.Add($stdout.GetAwaiter().GetResult())
    [void]$lines.Add($stderr.GetAwaiter().GetResult())
    $lines | Set-Content -LiteralPath $Log -Encoding utf8
    Get-Content -LiteralPath $Log -Tail 70 | Out-Host
    Require ($p.ExitCode -eq 0) "Subprocess failed with exit code $($p.ExitCode): $Executable; log=$Log"
  } catch {
    try { if (-not $p.HasExited) { $p.Kill($true) } } catch {}
    if ($stdout) {try{[void]$lines.Add($stdout.GetAwaiter().GetResult())}catch{}}
    if ($stderr) {try{[void]$lines.Add($stderr.GetAwaiter().GetResult())}catch{}}
    $lines | Set-Content -LiteralPath $Log -Encoding utf8
    throw
  } finally { $p.Dispose() }
}
function Assert-Archive([string]$File) {
  $exe=Get-7zip
  & $exe t -bso0 -bsp0 $File | Out-Host
  Require ($LASTEXITCODE -eq 0) "7z archive integrity failed: $File"
}
