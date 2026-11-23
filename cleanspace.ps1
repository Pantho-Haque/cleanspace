# cleanspace for Windows: free disk space without losing anything you care about.
#
# Usage: cleanspace [options]          (the installer also adds the command: clean)
#   (no option)       scan, show what can go and how each item comes back, ask, then clean
#   --deep [dir]      also browser caches, the Recycle Bin, and build folders
#                     (node_modules, target, ...) of projects under dir or your code folders
#   --older DAYS      with --deep, keep builds of projects edited in the last DAYS days (default 14)
#   -n, --dry-run     show the plan only, delete nothing
#   -y, --yes         clean without asking (needed when not run from a terminal)
#   --review          go through personal space hogs one at a time, asking before each
#   --stats           space freed so far, and which caches grow back fastest
#   --schedule [daily|weekly|off]
#                     clean automatically whenever free space drops below a limit (default 20G)
#   --auto            what the schedule runs: clean only if free space is below the limit
#   --config          show the config file (exclusions, code folders, limits), creating it if needed
#   --update          update to the latest version
#   --remove          uninstall cleanspace with its schedule, settings and history
#   --version, -h, --help
#
# Exit codes: 0 done, 1 error, 2 confirmation needed (no terminal, use --yes).
# Works with Windows PowerShell 5.1 (built into Windows 10/11) and PowerShell 7. Plain ASCII on purpose:
# PowerShell 5.1 reads scripts without a BOM as the local code page.

$VERSION = '2.2.0'
$RAW = 'https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main'
$SELF = $PSCommandPath
$argv = @($args)
$IC = [Globalization.CultureInfo]::InvariantCulture
$IsWin = $env:OS -eq 'Windows_NT'

$H = $env:USERPROFILE; $L = $env:LOCALAPPDATA; $A = $env:APPDATA; $TMP = $env:TEMP
if (-not $H -or -not $L -or -not $A) { Write-Host 'cleanspace: USERPROFILE, LOCALAPPDATA and APPDATA must be set'; exit 1 }
if ($TMP -and $TMP.Contains('~') -and (Test-Path -LiteralPath (Join-Path $L 'Temp'))) { $TMP = Join-Path $L 'Temp' }   # 8.3 short form
if ($TMP) {   # only trust TEMP as a place to delete when it is its own folder, not a drive root or a parent of the profile
  $t = $TMP.TrimEnd('\')
  if ($t.Length -le 3 -or @(@($H, $L, $A) | Where-Object { ($_.TrimEnd('\') + '\').StartsWith($t + '\', 'OrdinalIgnoreCase') }).Count) { $TMP = $null }
}
$HOMEDIR = Join-Path $L 'cleanspace'                      # cleanspace.ps1, bin\ (command shims) and state\ live here
$STATE = Join-Path $HOMEDIR 'state'
$CONF = Join-Path (Join-Path $A 'cleanspace') 'config'
$HIST = Join-Path $STATE 'history.tsv'
$TASK = 'cleanspace'

$UseColor = (-not $env:NO_COLOR) -and (-not [Console]::IsOutputRedirected)
$Answers = $null
if ($env:CLEANSPACE_INPUT) {   # tests feed answers from a file
  $Answers = New-Object System.Collections.Queue
  Get-Content -LiteralPath $env:CLEANSPACE_INPUT | ForEach-Object { $Answers.Enqueue($_) }
}
$CanAsk = ($null -ne $Answers) -or ((-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected) -and [Environment]::UserInteractive)

function Say([string]$t = '', [string]$c = '', [switch]$NoNewline) {
  if ($UseColor -and $c) { Write-Host $t -ForegroundColor $c -NoNewline:$NoNewline } else { Write-Host $t -NoNewline:$NoNewline }
}
function Fail([string]$m) { Say "cleanspace: $m" Red; exit 1 }
function Warn([string]$m) { Say "! $m" Yellow }
function Ok([string]$m) { Say "OK  $m" Green }
function Human([long]$k) {
  if ($k -ge 1073741824) { return [string]::Format($IC, '{0:0.0}T', $k / 1073741824) }
  if ($k -ge 1048576) { return [string]::Format($IC, '{0:0.0}G', $k / 1048576) }
  if ($k -ge 1024) { return [string]::Format($IC, '{0:0}M', $k / 1024) }
  return "${k}K"
}
function Tilde([string]$p) { if ($p.StartsWith($H, 'OrdinalIgnoreCase')) { return '~' + $p.Substring($H.Length) }; return $p }
function Get-Drive { New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($H)) }
function FreeKB { [long]((Get-Drive).AvailableFreeSpace / 1024) }
function DiskFree {
  $d = Get-Drive
  $used = 100 - [math]::Round(100 * $d.AvailableFreeSpace / $d.TotalSize)
  return "$(Human ([long]($d.AvailableFreeSpace / 1024))) free ($used% used)"
}
function Read-Answer([string]$prompt) {
  Say $prompt -NoNewline
  if ($null -ne $Answers) {
    if ($Answers.Count -eq 0) { Say ''; return $null }
    $a = [string]$Answers.Dequeue(); Say $a; return $a
  }
  return (Read-Host)
}
function Show-Progress([string]$label) { if ($UseColor) { Say ("`r  scanning $label...".PadRight(79)) DarkGray -NoNewline } }
function Clear-Progress { if ($UseColor) { Write-Host ("`r" + (' ' * 79) + "`r") -NoNewline } }

# ---------------------------------------------------------------- arguments
$DEEP = $false; $DRY = $false; $YES = $false; $AUTO = $false; $ACTION = ''; $SCHED = ''; $OLDER = -1; $DIRS = @()
for ($i = 0; $i -lt $argv.Count; $i++) {
  $opt = [string]$argv[$i]   # not $a: PowerShell names ignore case, and $A is APPDATA
  $next = ''; if ($i + 1 -lt $argv.Count) { $next = [string]$argv[$i + 1] }
  if ($opt -eq '--deep') {
    $DEEP = $true
    if ($next -and -not $next.StartsWith('-')) {
      if (-not (Test-Path -LiteralPath $next -PathType Container)) { Fail "no such folder: $next" }
      $DIRS += $next; $i++
    }
  }
  elseif ($opt -eq '--older') { if ($next -notmatch '^\d+$') { Fail '--older needs a number of days' }; $OLDER = [int]$next; $i++ }
  elseif ($opt -eq '-n' -or $opt -eq '--dry-run') { $DRY = $true }
  elseif ($opt -eq '-y' -or $opt -eq '--yes') { $YES = $true }
  elseif ($opt -eq '--auto') { $AUTO = $true; $YES = $true }
  elseif ($opt -eq '--schedule') {
    $ACTION = $opt; $SCHED = 'daily'
    if ($next -eq 'daily' -or $next -eq 'weekly' -or $next -eq 'off') { $SCHED = $next; $i++ }
  }
  elseif (@('--review', '--stats', '--config', '--update', '--remove', '--version', '-h', '--help') -contains $opt) { $ACTION = $opt }
  else { Fail "unknown option: $opt (see cleanspace --help)" }
}

# ---------------------------------------------------------------- config
$Excl = @(); $CDirs = @(); $AutoGB = 20; $OlderConf = 14
function Expand-Home([string]$v) { if ($v -eq '~' -or $v.StartsWith('~/') -or $v.StartsWith('~\')) { return $H + $v.Substring(1).Replace('/', '\') }; return $v }
if (Test-Path -LiteralPath $CONF) {
  foreach ($line in Get-Content -LiteralPath $CONF) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    if ($t -notmatch '=') { Warn "config: ignoring '$t'"; continue }
    $k = $t.Substring(0, $t.IndexOf('=')).Trim(); $v = Expand-Home ($t.Substring($t.IndexOf('=') + 1).Trim())
    if ($k -eq 'exclude') { $Excl += $v.TrimEnd('\') }
    elseif ($k -eq 'deep_dir') { $CDirs += $v }
    elseif ($k -eq 'older_days') { if ($v -match '^\d+$') { $OlderConf = [int]$v } else { Warn 'config: older_days must be a number' } }
    elseif ($k -eq 'auto_below_gb') { if ($v -match '^\d+$') { $AutoGB = [int]$v } else { Warn 'config: auto_below_gb must be a number' } }
    else { Warn "config: unknown setting '$k'" }
  }
}
if ($OLDER -lt 0) { $OLDER = $OlderConf }

# ---------------------------------------------------------------- simple actions
function Get-ScheduleStatus {
  $t = Get-ScheduledTask -TaskName $TASK -ErrorAction SilentlyContinue
  if (-not $t) { return 'off' }
  if ($t.Triggers[0].CimClass.CimClassName -like '*Weekly*') { return 'weekly' }
  return 'daily'
}
function Set-Schedule([string]$when) {
  Unregister-ScheduledTask -TaskName $TASK -Confirm:$false -ErrorAction SilentlyContinue
  if ($when -eq 'off') { return }
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SELF`" --auto"
  if ($when -eq 'weekly') { $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '11:00' }
  else { $trg = New-ScheduledTaskTrigger -Daily -At '11:00' }
  $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
  try {
    Register-ScheduledTask -TaskName $TASK -Action $act -Trigger $trg -Settings $set -Force `
      -Description 'cleanspace: clean caches when disk space is low' -ErrorAction Stop | Out-Null
  } catch { Fail "could not create the scheduled task: $($_.Exception.Message)" }
}

function Notify([string]$m) {
  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information; $n.Visible = $true
    $n.ShowBalloonTip(10000, 'cleanspace', $m, 'Info'); Start-Sleep -Seconds 6; $n.Dispose()
  } catch { }
}

function Show-Stats {
  Say 'cleanspace stats' White
  $s = Get-ScheduleStatus
  if ($s -eq 'off') { Say '  Schedule: off  (turn on with: cleanspace --schedule)' }
  else { Say "  Schedule: $s, cleans when free space is below ${AutoGB}G  (log: $(Tilde (Join-Path $STATE 'auto.log')))" }
  if (-not (Test-Path -LiteralPath $HIST)) { Say '  No cleans recorded yet. Run clean to start.'; return }
  $rows = @(Get-Content -LiteralPath $HIST | Where-Object { $_ } | ForEach-Object {
      $f = $_.Split("`t"); [pscustomobject]@{ T = [long]$f[0]; Label = $f[1]; Before = [long]$f[2]; Freed = [long]$f[3] } })
  if ($rows.Count -eq 0) { Say '  No cleans recorded yet.'; return }
  $runs = @($rows | Select-Object -ExpandProperty T -Unique).Count
  $total = ($rows | Measure-Object Freed -Sum).Sum
  $first = [DateTimeOffset]::FromUnixTimeSeconds([long]($rows | Measure-Object T -Minimum).Minimum).LocalDateTime.ToString('yyyy-MM-dd')
  Say "  Freed $(Human $total) over $runs cleans since $first" Green
  Say ''; Say 'Biggest wins' White
  $rows | Group-Object Label | ForEach-Object { [pscustomobject]@{ L = $_.Name; K = ($_.Group | Measure-Object Freed -Sum).Sum } } |
    Where-Object { $_.K -gt 0 } | Sort-Object K -Descending | Select-Object -First 5 |
    ForEach-Object { Say ('  {0,-30} {1,7}' -f $_.L, (Human $_.K)) }
  # Regrowth: what an item had grown back to at each clean, divided by the time since the clean before.
  $last = @{}; $g = @{}; $dt = @{}
  foreach ($r in ($rows | Sort-Object T)) {
    if ($last.ContainsKey($r.Label) -and $r.T -gt $last[$r.Label]) { $g[$r.Label] += $r.Before; $dt[$r.Label] += $r.T - $last[$r.Label] }
    $last[$r.Label] = $r.T
  }
  Say ''; Say 'Fastest to grow back  (per week, measured between cleans)' White
  $grow = @($g.Keys | Where-Object { $dt[$_] -ge 86400 -and $g[$_] -gt 0 } |
      ForEach-Object { [pscustomobject]@{ L = $_; K = [long]($g[$_] / $dt[$_] * 604800) } } | Sort-Object K -Descending | Select-Object -First 5)
  if ($grow.Count -eq 0) { Say '  needs two cleans at least a day apart' DarkGray }
  else { $grow | ForEach-Object { Say ('  {0,-30} {1,7}/week' -f $_.L, (Human $_.K)) } }
}

if ($ACTION -eq '-h' -or $ACTION -eq '--help') {
  foreach ($line in (Get-Content -LiteralPath $SELF | Select-Object -Skip 1)) { if (-not $line.StartsWith('#')) { break }; $line -replace '^# ?', '' }
  exit 0
}
if ($ACTION -eq '--version') { "cleanspace $VERSION"; exit 0 }
if ($ACTION -eq '--stats') { Show-Stats; exit 0 }
if ($ACTION -eq '--config') {
  if (-not (Test-Path -LiteralPath $CONF)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $CONF) | Out-Null
    @'
# cleanspace settings. One "key = value" per line; lines starting with # are ignored.

# Never touch something. Matches an item's name (as shown in the plan) or a path, and
# accepts * wildcards. Repeat the line for more.
# exclude = Docker images & build cache
# exclude = ~\AppData\Local\Temp
# exclude = ~\source\repos\keep-this-project\*

# Folders --deep searches for project build folders. Repeat for more.
# Default: whichever of Desktop, Documents, ~\source\repos, ~\code, ~\dev, ~\projects, ~\src, ~\repos, ~\work exist.
# deep_dir = ~\code

# With --deep, keep builds of projects edited in the last N days (0 = clean all).
# older_days = 14

# The schedule (cleanspace --schedule) only cleans when free space is below this many GB.
# auto_below_gb = 20
'@ | Set-Content -LiteralPath $CONF -Encoding UTF8
    Ok "created $(Tilde $CONF)"
  }
  Say "Config file: $(Tilde $CONF)  (edit it with: notepad `"$CONF`")"; Say ''
  $active = @(Get-Content -LiteralPath $CONF | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
  if ($active.Count) { $active } else { Say '(everything is commented out, so the defaults apply)' DarkGray }
  exit 0
}
if ($ACTION -eq '--schedule') {
  if ($SCHED -eq 'off') { Set-Schedule off; Ok 'schedule removed'; exit 0 }
  Set-Schedule $SCHED
  Ok "cleanspace will check $SCHED and clean caches when free space is below ${AutoGB}G"
  Say '    It never touches --deep or --review items. Change the limit with cleanspace --config; stop with --schedule off.' DarkGray
  exit 0
}
if ($ACTION -eq '--update') {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $dl = "$SELF.tmp"
  try { Invoke-WebRequest -UseBasicParsing -Uri "$RAW/cleanspace.ps1" -OutFile $dl -ErrorAction Stop } catch { Remove-Item $dl -ErrorAction SilentlyContinue; Fail 'download failed' }
  $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($dl, [ref]$null, [ref]$errs)
  $m = Select-String -LiteralPath $dl -Pattern "^\`$VERSION = '([^']+)'" | Select-Object -First 1
  if ($errs.Count -or -not $m) { Remove-Item $dl -ErrorAction SilentlyContinue; Fail "downloaded file looks broken, kept $VERSION" }
  $new = $m.Matches[0].Groups[1].Value
  if ($new -eq $VERSION) { Remove-Item $dl; Ok "already up to date ($VERSION)"; exit 0 }
  Move-Item -LiteralPath $dl -Destination $SELF -Force
  Ok "updated cleanspace $VERSION -> $new"; exit 0
}
if ($ACTION -eq '--remove') {
  if ((Get-ScheduleStatus) -ne 'off') { Set-Schedule off }
  Remove-Item -LiteralPath (Split-Path $CONF) -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $STATE -Recurse -Force -ErrorAction SilentlyContinue
  $bin = Join-Path $HOMEDIR 'bin'
  $key = Get-Item -LiteralPath 'HKCU:\Environment' -ErrorAction SilentlyContinue
  if ($key) {   # read and write PATH unexpanded, so entries like %USERPROFILE%\... stay as they are
    $p = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $new = (@($p.Split(';') | Where-Object { $_ -and $_.TrimEnd('\') -ne $bin }) -join ';')
    if ($new -ne $p) { Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -Value $new -Type ExpandString }
  }
  Remove-Item -LiteralPath $bin -Recurse -Force -ErrorAction SilentlyContinue
  if ($SELF.StartsWith($HOMEDIR + '\', 'OrdinalIgnoreCase')) { Remove-Item -LiteralPath $SELF -Force -ErrorAction SilentlyContinue }   # not a git checkout
  if ((Test-Path -LiteralPath $HOMEDIR) -and -not (Get-ChildItem -LiteralPath $HOMEDIR -Force)) { Remove-Item -LiteralPath $HOMEDIR -Force }
  Ok 'cleanspace removed with its schedule, settings and history (open a new terminal to drop the commands)'
  exit 0
}

# ---------------------------------------------------------------- scanning
# Every item is measured first; nothing is deleted until the plan is confirmed.
$Items = New-Object System.Collections.ArrayList
$Covered = New-Object System.Collections.ArrayList
$Roots = @(); $Sect = ''; $SBack = ''; $script:KeptNote = ''

function Section([string]$name, [string]$back) { $script:Sect = $name; $script:SBack = $back }

function Test-Excluded([string]$s) {
  foreach ($pat in $Excl) {
    if ($s -like $pat -or $s -like "$pat\*") { return $true }
    if ($pat.StartsWith("$s\", 'OrdinalIgnoreCase')) { return $true }   # an excluded path inside this one
  }
  return $false
}

function Test-SafePath([string]$p) {   # only ever delete inside the profile, AppData, Temp, or folders given to --deep
  if (-not $p -or $p -match '(^|\\)\.\.(\\|$)') { return $false }
  foreach ($r in (@($H, $L, $A, $TMP) + $script:Roots)) {
    if ($r -and $p.StartsWith($r.TrimEnd('\') + '\', 'OrdinalIgnoreCase')) { return $true }
  }
  return $false
}

# Size in KB. Never follows junctions or symlinks (pnpm and npm link use them).
function Get-SizeKB([string[]]$paths) {
  $total = [long]0
  foreach ($p in $paths) {
    if (-not $p) { continue }
    $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if (-not $it -or ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    if (-not $it.PSIsContainer) { $total += $it.Length; continue }
    $stack = New-Object System.Collections.Stack; $stack.Push($it)
    while ($stack.Count -gt 0) {
      $d = $stack.Pop()
      try {
        foreach ($e in $d.EnumerateFileSystemInfos()) {
          if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
          if ($e -is [IO.DirectoryInfo]) { $stack.Push($e) } else { $total += $e.Length }
        }
      } catch { }
    }
  }
  return [long][math]::Floor($total / 1024)
}

# Add-Item label paths [-Back kind] [-Guard process] [-GuardCmd text] [-Tool name -Run {command}] [-NeedTool] [-Size kb]
#   Back: how it comes back (auto | dl | build | gone | manual:<command>). Guard: skip while that process runs.
#   GuardCmd: skip while any running program's command line contains that text.
#   Tool/Run: use the tool's own clean command when the tool is installed. NeedTool: skip otherwise.
function Add-Item {
  param([string]$Label, [string[]]$Paths = @(), [string]$Back = '', [string]$Guard = '', [string]$GuardCmd = '', [string]$Tool = '',
    [scriptblock]$Run = $null, [switch]$NeedTool, [long]$Size = -1, [string]$Status = '', [string]$Why = '')
  $had = @($Paths | Where-Object { $_ }).Count -gt 0
  $keep = @()
  foreach ($p in $Paths) {
    if (-not $p) { continue }
    $p = $p.TrimEnd('\')
    if ((Test-SafePath $p) -and -not (Test-Excluded $p)) { $keep += $p; [void]$Covered.Add($p) }
  }
  Show-Progress $Label
  if ($Size -ge 0) { $k = $Size } else { $k = Get-SizeKB $keep }
  $st = 'todo'
  if ($Status) { $st = $Status }
  elseif ((Test-Excluded $Label) -or ($had -and $keep.Count -eq 0)) { $st = 'excluded' }
  elseif ($k -le 0) { $st = 'clean' }
  elseif ($Guard -and (Get-Process -Name $Guard -ErrorAction SilentlyContinue)) { $st = 'skip'; $Why = "$Guard is running" }
  elseif ($GuardCmd -and (Test-CmdLine $GuardCmd)) { $st = 'skip'; $Why = 'a running program uses it' }
  elseif ($NeedTool -and -not (Get-Command $Tool -ErrorAction SilentlyContinue)) { $st = 'skip'; $Why = "$Tool is not on PATH" }
  if (-not $Back) { $Back = $script:SBack }
  if ($st -eq 'todo' -and $AUTO -and $Back.StartsWith('manual:')) { $st = 'skip'; $Why = 'needs a manual reinstall, so the schedule leaves it' }
  [void]$Items.Add([pscustomobject]@{ Label = $Label; Section = $script:Sect; KB = [long]$k; Status = $st; Why = $Why
      Back = $Back; Paths = $keep; Tool = $Tool; Run = $Run })
}

function Test-CmdLine([string]$text) {   # does any running program's command line contain $text?
  try { return [bool](Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($text) } | Select-Object -First 1) }
  catch { return $false }
}
function Get-ObsoleteExtensions {   # extensions VS Code / Cursor marked obsolete (replaced by a newer version)
  foreach ($dir in "$H\.vscode\extensions", "$H\.vscode-insiders\extensions", "$H\.cursor\extensions", "$H\.windsurf\extensions") {
    $f = Join-Path $dir '.obsolete'
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $raw = Get-Content -LiteralPath $f -Raw
    foreach ($m in [regex]::Matches($raw, '"([^"/\\]+)"\s*:\s*true')) {
      $p = Join-Path $dir $m.Groups[1].Value
      if (Test-Path -LiteralPath $p -PathType Container) { $p }
    }
  }
}
function Get-Older([string]$dir, [int]$keep) {   # entries of $dir except the newest $keep
  if (-not (Test-Path -LiteralPath $dir)) { return }
  Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $keep | ForEach-Object { $_.FullName }
}
function Get-OldEntries([string]$dir, [int]$days) {   # entries of $dir untouched for $days days
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
  $cut = (Get-Date).AddDays(-$days)
  Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut } | ForEach-Object { $_.FullName }
}
function Get-OldJetBrains([string]$dir) {   # JetBrains keeps a cache per IDE version; keep the newest of each
  if (-not (Test-Path -LiteralPath $dir)) { return }
  $seen = @{}
  Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object {
    $prod = $_.Name -replace '[\d.]+$', ''
    if ($seen.ContainsKey($prod)) { $_.FullName } else { $seen[$prod] = 1 }
  }
}
# Electron apps (Slack, Discord, VS Code, Postman, ...) keep caches under AppData\Roaming\<app>. Only apps with a
# Chromium marker folder count, so a non-Electron app's own folder called "Cache" is left alone.
function Find-AppCaches {
  $markers = @('Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'GrShaderCache')
  $names = @('Cache', 'Code Cache', 'GPUCache', 'CachedData', 'CachedExtensionVSIXs', 'DawnCache', 'DawnGraphiteCache',
    'GraphiteDawnCache', 'DawnWebGPUCache', 'GrShaderCache', 'ShaderCache', 'Crashpad\completed')
  Get-ChildItem -LiteralPath $A -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'cleanspace' } | ForEach-Object {
    $app = $_.FullName
    if (-not @($markers | Where-Object { Test-Path -LiteralPath (Join-Path $app $_) }).Count) { return }
    foreach ($n in $names) { $p = Join-Path $app $n; if (Test-Path -LiteralPath $p -PathType Container) { $p } }
  }
}
function Get-ChromiumCaches([string]$ud) {   # cache folders of every profile; the profiles themselves are never touched
  if (-not (Test-Path -LiteralPath $ud)) { return }
  foreach ($n in 'ShaderCache', 'GrShaderCache', 'GraphiteDawnCache', 'component_crx_cache') { $p = Join-Path $ud $n; if (Test-Path -LiteralPath $p) { $p } }
  Get-ChildItem -LiteralPath $ud -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' } | ForEach-Object {
      foreach ($n in 'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'GrShaderCache', 'GraphiteDawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'Application Cache') {
        $p = Join-Path $_.FullName $n; if (Test-Path -LiteralPath $p) { $p }
      }
    }
}
function Get-FirefoxCaches {
  $pr = Join-Path $L 'Mozilla\Firefox\Profiles'
  if (-not (Test-Path -LiteralPath $pr)) { return }
  Get-ChildItem -LiteralPath $pr -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    foreach ($n in 'cache2', 'startupCache') { $p = Join-Path $_.FullName $n; if (Test-Path -LiteralPath $p) { $p } }
  }
}
function Get-RecycleKB {   # this user's Recycle Bin on the system drive
  if (-not $IsWin) { return [long]0 }
  try { $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { return [long]0 }
  return Get-SizeKB @(Join-Path "$env:SystemDrive\" "`$Recycle.Bin\$sid")
}
function Get-DockerKB {   # reclaimable image + build cache size (docker reports SI units)
  $s = 0.0
  foreach ($line in (& docker system df --format '{{.Type}}|{{.Reclaimable}}' 2>$null)) {
    $f = $line.Split('|'); if ($f[0] -notmatch 'Images|Build') { continue }
    if ($f[1] -match '^([\d.]+)\s*([kKMGT]?B)') {
      $m = @{ 'B' = 1; 'KB' = 1e3; 'MB' = 1e6; 'GB' = 1e9; 'TB' = 1e12 }[$Matches[2]]   # keys ignore case: kB finds KB
      $s += [double]::Parse($Matches[1], $IC) * $m / 1024
    }
  }
  return [long]$s
}

# Build folders and the project file that must sit next to each (so a random "target" or "build" is never touched).
$BuildNames = @('node_modules', '.next', '.nuxt', '.svelte-kit', '.angular', '.astro', '.expo', '.metro', '.turbo', '.parcel-cache',
  'target', '.xwin-cache', '.gradle', 'build', 'cmake-build-debug', 'cmake-build-release', 'Pods', 'vendor', '.dart_tool', '.build',
  '.zig-cache', 'zig-cache', 'zig-out', '_build', '.elixir_ls', '.elixir-tools', '.lexical', '.stack-work', 'dist-newstyle', 'elm-stuff',
  'bin', 'obj', 'Library', 'Temp', 'Binaries', 'Intermediate', 'DerivedDataCache', '.godot', '.terraform', '.pixi',
  '.terragrunt-cache', '.output', 'coverage', 'DerivedData', '.cxx', '.venv', 'venv',
  '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', '.nox', '__pypackages__')
$PyCaches = @('__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', '.nox', '__pypackages__')

function Test-Owned([string]$name, [string]$p) {
  function has([string]$f) { Test-Path -LiteralPath (Join-Path $p $f) }
  function any([string]$g) { [bool](Get-ChildItem -LiteralPath $p -Filter $g -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) }
  switch -CaseSensitive ($name) {
    { @('node_modules', '.next', '.nuxt', '.output', '.svelte-kit', '.angular', '.astro', '.expo', '.metro', '.turbo', '.parcel-cache', 'coverage') -ccontains $_ } { return (has 'package.json') }
    'DerivedData' { return ((any '*.xcodeproj') -or (any '*.xcworkspace')) }
    '.cxx' { return (any 'build.gradle*') }
    '.terragrunt-cache' { return (has 'terragrunt.hcl') }
    'target' { return ((has 'Cargo.toml') -or (has 'pom.xml') -or (has 'build.sbt')) }
    '.xwin-cache' { return (has 'Cargo.toml') }
    '.gradle' { return ((any 'build.gradle*') -or (any 'settings.gradle*')) }
    'build' { return ((any 'build.gradle*') -or (has 'CMakeLists.txt') -or (has 'pubspec.yaml')) }
    { $_ -like 'cmake-build-*' } { return (has 'CMakeLists.txt') }
    'Pods' { return (has 'Podfile') }
    'vendor' { return (has 'composer.json') }
    '.dart_tool' { return (has 'pubspec.yaml') }
    '.build' { return (has 'Package.swift') }
    { @('.zig-cache', 'zig-cache', 'zig-out') -ccontains $_ } { return (has 'build.zig') }
    { @('_build', '.elixir_ls', '.elixir-tools', '.lexical') -ccontains $_ } { return (has 'mix.exs') }
    '.stack-work' { return (has 'stack.yaml') }
    'dist-newstyle' { return ((has 'cabal.project') -or (any '*.cabal')) }
    'elm-stuff' { return (has 'elm.json') }
    { @('bin', 'obj') -ccontains $_ } { return ((any '*.csproj') -or (any '*.fsproj') -or (any '*.vbproj')) }
    { @('Library', 'Temp') -ccontains $_ } { return (has 'Assembly-CSharp.csproj') }   # Unity
    { @('Binaries', 'Intermediate', 'DerivedDataCache') -ccontains $_ } { return (any '*.uproject') }   # Unreal
    '.godot' { return (has 'project.godot') }
    '.terraform' { return (has '.terraform.lock.hcl') }
    '.pixi' { return (has 'pixi.toml') }
    { @('.venv', 'venv') -ccontains $_ } {   # a real virtualenv you can recreate
      return ((has "$name\pyvenv.cfg") -and ((has 'pyproject.toml') -or (has 'requirements.txt') -or (has 'Pipfile') -or (has 'setup.py'))) }
  }
  return $true   # Python bytecode and tool caches: always safe
}

# Was any source file in project $p edited in the last $days days? (Build folders and hidden folders don't count.)
function Test-Active([string]$p, [int]$days) {
  $cut = (Get-Date).AddDays(-$days)
  $q = New-Object System.Collections.Queue; $q.Enqueue(@((New-Object IO.DirectoryInfo $p), 0))
  while ($q.Count -gt 0) {
    $e = $q.Dequeue(); $d = $e[0]; $depth = $e[1]
    try {
      foreach ($f in $d.EnumerateFiles()) { if ($f.LastWriteTime -gt $cut) { return $true } }
      if ($depth -ge 2) { continue }
      foreach ($c in $d.EnumerateDirectories()) {
        if ($c.Name.StartsWith('.') -or $BuildNames -ccontains $c.Name -or ($c.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $q.Enqueue(@($c, ($depth + 1)))
      }
    } catch { }
  }
  return $false
}

# Your own data inside a build folder: a nested git repo, or keys (Solana/Anchor keeps program keys in target\deploy).
function Test-HoldsData([IO.DirectoryInfo]$dir) {
  $q = New-Object System.Collections.Queue; $q.Enqueue(@($dir, 0))
  while ($q.Count -gt 0) {
    $e = $q.Dequeue()
    try {
      foreach ($c in $e[0].EnumerateFileSystemInfos()) {
        if ($c.Name -eq '.git' -or $c.Name -like '*-keypair.json') { return $true }
        if ($c -is [IO.DirectoryInfo] -and $e[1] -lt 2 -and -not ($c.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $q.Enqueue(@($c, ($e[1] + 1))) }
      }
    } catch { }
  }
  return $false
}

function Find-ProjectBuilds {
  if ($script:Roots.Count -eq 0) { return }
  # ponytail: a folder named like a build folder is never searched inside, so projects nested under e.g. a "bin" folder are missed.
  $groups = @{}; $kept = 0; $tracked = 0
  $git = [bool](Get-Command git -ErrorAction SilentlyContinue)
  $skip = @($L, $A, (Join-Path $H 'AppData'))
  $stack = New-Object System.Collections.Stack
  foreach ($r in $script:Roots) { $stack.Push((New-Object IO.DirectoryInfo $r)) }
  while ($stack.Count -gt 0) {
    $d = $stack.Pop()
    try { $kids = @($d.GetDirectories()) } catch { continue }
    foreach ($k in $kids) {
      if ($k.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
      $name = $k.Name
      if ($BuildNames -ccontains $name) {
        $p = $d.FullName
        if (-not (Test-Owned $name $p)) { continue }
        if ($PyCaches -notcontains $name) {
          if ($OLDER -gt 0 -and (Test-Active $p $OLDER)) { $kept++; continue }
          if ($git -and (& git -C $p ls-files -- $name 2>$null | Select-Object -First 1)) { $tracked++; continue }   # committed: keep
          if (Test-HoldsData $k) { $tracked++; continue }   # a nested repo or keys inside
        }
        if (-not $groups.ContainsKey($name)) { $groups[$name] = New-Object System.Collections.ArrayList }
        [void]$groups[$name].Add($k.FullName)
        continue
      }
      if ($name.StartsWith('.') -or ($k.Attributes -band [IO.FileAttributes]::Hidden) -or $skip -contains $k.FullName) { continue }
      $stack.Push($k)
    }
  }
  foreach ($n in ($groups.Keys | Sort-Object)) { Add-Item "$n ($($groups[$n].Count))" @($groups[$n]) }
  if ($kept) { $script:KeptNote = "$kept build folders kept: their projects were edited in the last $OLDER days (--older 0 to include them)" }
  if ($tracked) { $script:KeptNote = (@($script:KeptNote, "$tracked kept because they are in git or hold a repo or keys") | Where-Object { $_ }) -join '; ' }
}

function Invoke-Scan {
  Section 'Package managers' 'dl'
  Add-Item 'npm cache' @("$L\npm-cache\_cacache", "$L\npm-cache\_logs", "$L\npm-cache\_prebuilds")
  Add-Item 'npx packages' @("$L\npm-cache\_npx") -GuardCmd '_npx'   # MCP servers and other tools run from here
  Add-Item 'pnpm store' @("$L\pnpm\store") -Tool pnpm -Run { pnpm store prune }
  Add-Item 'pnpm metadata cache' @(Get-ChildItem -LiteralPath "$L\pnpm-cache" -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'dlx' } | ForEach-Object { $_.FullName })
  Add-Item 'Corepack downloads' @("$L\node\corepack")
  Add-Item 'Yarn cache' @("$L\Yarn\Cache", "$L\Yarn\Berry\cache")
  Add-Item 'Bun cache' @("$H\.bun\install\cache")
  Add-Item 'Deno cache' @("$L\deno\deps", "$L\deno\npm", "$L\deno\gen", "$L\deno\remote")   # not location_data: app localStorage
  Add-Item 'uv cache' @("$L\uv\cache") -Tool uv -Run { uv cache clean }
  Add-Item 'pip / Pipenv cache' @("$L\pip\Cache", "$L\pipenv\pipenv\Cache")
  Add-Item 'Poetry cache' @("$L\pypoetry\Cache\cache", "$L\pypoetry\Cache\artifacts")
  Add-Item 'Conda packages' @("$H\miniconda3\pkgs", "$H\anaconda3\pkgs", "$H\miniforge3\pkgs", "$H\.conda\pkgs") -Tool conda -NeedTool -Run { conda clean --all --yes }
  Add-Item 'Composer cache' @("$L\Composer")
  Add-Item 'Go modules' @("$H\go\pkg\mod") -Tool go -Run { go clean -modcache }
  Add-Item 'Go build cache' @("$L\go-build") -Back auto
  Add-Item 'Cargo registry' @("$H\.cargo\registry\cache", "$H\.cargo\registry\src", "$H\.cargo\git\checkouts")
  Add-Item 'Gradle caches' @("$H\.gradle\caches", "$H\.gradle\daemon", "$H\.gradle\wrapper\dists")
  Add-Item 'Maven wrapper' @("$H\.m2\wrapper")
  Add-Item 'sbt / Coursier cache' @("$H\.ivy2\cache", "$L\Coursier\cache", "$H\.sbt\boot")
  Add-Item 'NuGet packages' @("$H\.nuget\packages", "$L\NuGet\v3-cache", "$L\NuGet\plugins-cache")
  Add-Item 'Dart / Flutter pub' @("$L\Pub\Cache\hosted", "$L\Pub\Cache\git")
  Add-Item 'Scoop downloads' @("$H\scoop\cache")
  Add-Item 'Chocolatey downloads' @("$TMP\chocolatey")
  Add-Item 'Terraform plugins' @("$A\terraform.d\plugin-cache")
  Add-Item 'vcpkg downloads' @("$L\vcpkg\archives", "$L\vcpkg\downloads")
  Add-Item 'rustup downloads' @("$H\.rustup\downloads", "$H\.rustup\tmp")
  Add-Item 'pyenv downloads' @("$H\.pyenv\pyenv-win\install_cache")

  Section 'Build & test tools' 'dl'
  Add-Item 'Playwright browsers' @("$L\ms-playwright") -Back 'manual:npx playwright install'
  Add-Item 'Puppeteer browsers' @("$H\.cache\puppeteer") -Back build
  Add-Item 'Cypress binaries' @("$L\Cypress\Cache") -Back build
  Add-Item 'Expo caches' @('expo-go', 'android-apk-cache', 'ios-simulator-app-cache', 'native-modules-cache', 'schema-cache', 'template-cache', 'versions-cache' | ForEach-Object { "$H\.expo\$_" })
  Add-Item 'Android build cache' @("$H\.android\build-cache", "$H\.android\cache") -Back auto
  Add-Item 'kubectl cache' @("$H\.kube\cache") -Back auto
  Add-Item 'Cloud CLI logs' @("$A\gcloud\logs", "$H\.azure\logs") -Back gone
  Add-Item 'Obsolete editor extensions' @(Get-ObsoleteExtensions)
  Add-Item 'Electron caches' @("$L\electron\Cache", "$L\electron-builder\Cache")
  Add-Item 'node-gyp headers' @("$L\node-gyp\Cache")
  Add-Item 'TypeScript cache' @("$L\Microsoft\TypeScript") -Back auto
  Add-Item 'Prisma engines' @("$H\.cache\prisma")
  Add-Item 'pre-commit envs' @("$H\.cache\pre-commit") -Back auto
  Add-Item 'Old JetBrains IDE caches' @(Get-OldJetBrains "$L\JetBrains") -Back auto
  Add-Item 'Visual Studio component cache' @("$L\Microsoft\VisualStudio\Packages\_Instances\_bootstrapper") -Back dl

  Section 'Windows' 'auto'
  Add-Item 'Temp files (2+ days old)' @(Get-OldEntries $TMP 2)
  Add-Item 'Crash dumps & error reports' @("$L\CrashDumps", "$L\Microsoft\Windows\WER\ReportArchive", "$L\Microsoft\Windows\WER\ReportQueue") -Back gone
  Add-Item 'GPU shader caches' @("$L\D3DSCache", "$L\NVIDIA\DXCache", "$L\NVIDIA\GLCache", "$L\AMD\DxCache", "$L\AMD\GLCache", "$L\Intel\ShaderCache")
  Add-Item 'Internet cache' @("$L\Microsoft\Windows\INetCache")

  Section 'Apps' 'auto'
  Add-Item 'Cursor caches' @("$A\Cursor\snapshots", "$A\Cursor\CachedExtensionVSIXs", "$A\Cursor\logs")
  Add-Item 'Electron app caches' @(Find-AppCaches)
  Add-Item 'Editor logs' @("$A\Code\logs", "$A\Code - Insiders\logs") -Back gone
  Add-Item 'Old Claude Code versions' @(Get-Older "$H\.local\share\claude\versions" 1) -Back dl
  Add-Item 'Old Cursor Agent versions' @(Get-Older "$H\.local\share\cursor-agent\versions" 1) -Back dl

  Section 'Docker' 'dl'
  Show-Progress 'Docker'
  if (Get-Command docker -ErrorAction SilentlyContinue) {
    & docker info *> $null
    if ($LASTEXITCODE -eq 0) {
      # Images no container uses and the build cache. Containers (even stopped ones) and volumes are kept.
      Add-Item 'Docker images & build cache' -Size (Get-DockerKB) -Tool docker -Run { docker image prune -a -f; docker builder prune -a -f }
    } else { Add-Item 'Docker' -Status skip -Why 'not running' }
  }

  if ($DEEP) {
    Section 'Browser caches (history, logins and bookmarks are kept)' 'auto'
    Add-Item 'Chrome cache' @(Get-ChromiumCaches "$L\Google\Chrome\User Data") -Guard chrome
    Add-Item 'Edge cache' @(Get-ChromiumCaches "$L\Microsoft\Edge\User Data") -Guard msedge
    Add-Item 'Brave cache' @(Get-ChromiumCaches "$L\BraveSoftware\Brave-Browser\User Data") -Guard brave
    Add-Item 'Vivaldi cache' @(Get-ChromiumCaches "$L\Vivaldi\User Data") -Guard vivaldi
    Add-Item 'Firefox cache' @(Get-FirefoxCaches) -Guard firefox
    Add-Item 'Chrome AI model' @("$L\Google\Chrome\User Data\OptGuideOnDeviceModel") -Guard chrome -Back dl

    Section 'Recycle Bin' 'gone'
    Add-Item 'Recycle Bin' -Size (Get-RecycleKB) -Tool Clear-RecycleBin -NeedTool -Run { Clear-RecycleBin -DriveLetter $env:SystemDrive.Substring(0, 1) -Force -ErrorAction SilentlyContinue }

    Section "Project builds ($((@($script:Roots | ForEach-Object { Tilde $_ })) -join ' '))" 'build'
    Find-ProjectBuilds
  }
}

function Note([string]$label, [string[]]$paths, [string]$hint = '') {   # report without deleting, if over 100M
  $k = Get-SizeKB $paths
  if ($k -gt 102400) { Say ('  .  {0,-30} {1,7}  {2}' -f $label, (Human $k), $(if ($hint) { $hint } else { Tilde $paths[0] })) DarkGray }
}
function Show-Notes {
  Say ''; Say 'Worth a look yourself  (never deleted here; clean --review goes through them)' White
  Note 'Downloads' @("$H\Downloads")
  if (-not $DEEP) { Say ('  .  {0,-30} {1,7}  {2}' -f 'Recycle Bin', (Human (Get-RecycleKB)), 'emptied by clean --deep') DarkGray }
  Note 'iPhone/iPad backups' @("$A\Apple Computer\MobileSync\Backup", "$H\Apple\MobileSync\Backup")
  Note 'Ollama models' @("$H\.ollama")
  Note 'Hugging Face models' @("$H\.cache\huggingface")
  Note 'Node versions (nvm)' @("$A\nvm")
  Note 'Android emulators' @("$H\.android\avd")
  Note 'Maven repository' @("$H\.m2\repository")
  foreach ($v in @(Get-ChildItem -Path "$L\Packages\*\LocalState\ext4.vhdx", "$L\Docker\wsl\*\*.vhdx" -Force -ErrorAction SilentlyContinue)) {
    Note "WSL/Docker disk ($($v.Directory.Parent.Name))" @($v.FullName) 'shrink with: wsl --manage <distro> --set-sparse true'
  }
  if (-not $DEEP) { Say '  Run clean --deep for browser caches, the Recycle Bin and old project builds.' DarkGray }
}

function Get-BackText([string]$b) {
  if ($b.StartsWith('manual:')) { return 'comes back with: ' + $b.Substring(7) }
  switch ($b) { 'auto' { 'rebuilds itself' } 'dl' { 're-downloads when needed' } 'build' { 'comes back on your next install/build' } 'gone' { 'permanent' } }
}

function Remove-Tree([string]$p) {   # delete without following junctions; keeps going past locked files
  if (-not (Test-SafePath $p)) { return }
  $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if (-not $it -or ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
  if (-not $it.PSIsContainer) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; return }
  if ($IsWin -and $p -notmatch '%') { & cmd.exe /d /c "rmdir /s /q `"$p`"" 2>$null | Out-Null }
  else { try { [IO.Directory]::Delete($p, $true) } catch { } }   # .NET does not follow junctions either
}

# ---------------------------------------------------------------- run
$LockFile = Join-Path $STATE 'lock'
$Locked = $false
function Lock {
  New-Item -ItemType Directory -Force -Path $STATE | Out-Null
  if (Test-Path -LiteralPath $LockFile) {
    $old = (Get-Content -LiteralPath $LockFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($old -match '^\d+$' -and (Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue)) { Fail "another cleanspace is already running (pid $old)" }
  }
  Set-Content -LiteralPath $LockFile -Value $PID; $script:Locked = $true
}

function Set-Roots {
  if (-not $DEEP) { return }
  $dirs = @($DIRS); if ($dirs.Count -eq 0) { $dirs = @($CDirs) }
  if ($dirs.Count -eq 0) {
    $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments')) +
      @('source\repos', 'code', 'dev', 'Development', 'projects', 'src', 'repos', 'GitHub', 'work', 'Workspace', 'www', 'Developer' | ForEach-Object { Join-Path $H $_ })
  }
  foreach ($d in $dirs) {
    if ($d -match '^[A-Za-z]:$') { $d += '\' }   # "C:" alone means the current folder on C:, not the drive
    if (-not $d -or -not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    $r = (Resolve-Path -LiteralPath $d).ProviderPath.TrimEnd('\')
    if ($r.Length -le 3) { Fail "refusing to search a whole drive ($r)" }
    if ($script:Roots -notcontains $r) { $script:Roots += $r }
  }
  if ($script:Roots.Count -eq 0) { Warn 'no code folders found; pass one with --deep DIR or set deep_dir in cleanspace --config' }
}

function Invoke-Review {
  if (-not $DRY -and -not $CanAsk) { Fail '--review needs an interactive terminal' }
  $script:total = [long]0; $script:trashed = [long]0
  Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
  function Ask([string]$q) {
    if ($DRY) { Say "$q [dry run: no]"; return $false }
    $a = Read-Answer "$q [y/N] "; return ($a -eq 'y' -or $a -eq 'Y' -or $a -eq 'yes')
  }
  function To-Trash([string]$p) {
    if (Test-Path -LiteralPath $p -PathType Container) {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin') }
  }
  function Pick([string]$dir, [string]$how) {   # ask about each entry of $dir over 100M, biggest first
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $list = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
      ForEach-Object { [pscustomobject]@{ P = $_.FullName; K = (Get-SizeKB @($_.FullName)) } } | Sort-Object K -Descending
    foreach ($e in $list) {
      if ($e.K -le 102400) { break }
      if (-not (Ask ('  {0,7}  {1}  -> {2}?' -f (Human $e.K), (Tilde $e.P), $how))) { continue }
      try {
        if ($how -eq 'trash') { To-Trash $e.P; $script:trashed += $e.K }
        else { Remove-Tree $e.P; if (-not (Test-Path -LiteralPath $e.P)) { $script:total += $e.K } }
      } catch { Warn "could not remove $($e.P): $($_.Exception.Message)" }
    }
  }

  Say 'Downloads  (moved to the Recycle Bin, so you can still restore them)' White
  Pick "$H\Downloads" trash

  $nv = $env:NVM_HOME; if (-not $nv) { $nv = "$A\nvm" }
  if (Test-Path -LiteralPath $nv) {
    Say ''; Say 'Node versions (nvm-windows)' White
    $cur = $null
    if ($env:NVM_SYMLINK -and (Test-Path -LiteralPath $env:NVM_SYMLINK)) { $cur = @((Get-Item -LiteralPath $env:NVM_SYMLINK -Force).Target)[0] }
    foreach ($v in @(Get-ChildItem -LiteralPath $nv -Directory -Filter 'v*' -ErrorAction SilentlyContinue)) {
      if ($cur -and $cur.TrimEnd('\') -eq $v.FullName) { Say ('  .  {0,-8} in use, kept' -f $v.Name) DarkGray; continue }
      $k = Get-SizeKB @($v.FullName)
      if (Ask ('  {0,7}  Node {1} -> delete?' -f (Human $k), $v.Name)) {
        Remove-Tree $v.FullName; if (-not (Test-Path -LiteralPath $v.FullName)) { $script:total += $k }
      }
    }
  }

  Say ''; Say 'Other personal data' White
  Pick "$A\Apple Computer\MobileSync\Backup" delete
  Pick "$H\Apple\MobileSync\Backup" delete
  Pick "$H\.cache\huggingface\hub" delete
  Pick "$H\.android\avd" delete

  Say ''; Say 'Large files untouched for 6 months  (over 1G, outside hidden folders and AppData; moved to the Recycle Bin)' White
  $cut = (Get-Date).AddDays(-180)
  $stack = New-Object System.Collections.Stack; $stack.Push((New-Object IO.DirectoryInfo $H))
  $found = New-Object System.Collections.ArrayList
  while ($stack.Count -gt 0) {
    $d = $stack.Pop()
    try {
      foreach ($f in $d.EnumerateFiles()) { if ($f.Length -gt 1GB -and $f.LastWriteTime -lt $cut) { [void]$found.Add($f) } }
      foreach ($c in $d.EnumerateDirectories()) {
        if ($c.Name.StartsWith('.') -or ($c.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::ReparsePoint))) { continue }
        if (@('AppData', 'Downloads') -contains $c.Name -and $d.FullName -eq $H) { continue }
        $stack.Push($c)
      }
    } catch { }
  }
  foreach ($f in $found) {
    $k = [long]($f.Length / 1024)
    if (Ask ('  {0,7}  {1}  -> Recycle Bin?' -f (Human $k), (Tilde $f.FullName))) { To-Trash $f.FullName; $script:trashed += $k }
  }

  Say ''
  Say "Deleted: $(Human $script:total)   Moved to the Recycle Bin: $(Human $script:trashed)  (empty it to free the space)" White
  if (-not $DRY -and $script:total -gt 0) {
    New-Item -ItemType Directory -Force -Path $STATE | Out-Null
    Add-Content -LiteralPath $HIST -Value ("{0}`treview`t{1}`t{1}" -f [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), $script:total)
  }
}

$total = [long]0
try {
  if ($ACTION -eq '--review') {
    if (-not $DRY) { Lock }
    Invoke-Review
    exit 0
  }

  if ($AUTO) {
    New-Item -ItemType Directory -Force -Path $STATE | Out-Null
    $log = Join-Path $STATE 'auto.log'
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB) {
      $tail = Get-Content -LiteralPath $log -Tail 500; Set-Content -LiteralPath $log -Value $tail
    }
    Start-Transcript -LiteralPath $log -Append | Out-Null
    if ((FreeKB) -ge ([long]$AutoGB * 1048576)) { Say "$(DiskFree): above the ${AutoGB}G limit, nothing to do"; exit 0 }
  }

  if (-not $DRY) { Lock }
  Set-Roots
  Say "Before: $(DiskFree)" White -NoNewline
  if ($DRY) { Say '  (dry run, nothing is deleted)' Yellow } else { Say '' }
  Invoke-Scan
  Clear-Progress

  # ---------------------------------------------------------------- plan
  $todo = New-Object System.Collections.ArrayList
  $planKB = [long]0; $nClean = 0; $nExcl = 0; $last = ''
  foreach ($it in $Items) {
    if ($it.Status -eq 'clean') { $nClean++; continue }
    if ($it.Status -eq 'excluded') { $nExcl++; continue }
    if ($it.Section -ne $last) { Say ''; Say $it.Section White; $last = $it.Section }
    if ($it.Status -eq 'skip') {
      $sz = ''; if ($it.KB -gt 0) { $sz = Human $it.KB }
      Say ('  .    {0,-30} {1,7}  skipped: {2}' -f $it.Label, $sz, $it.Why) DarkGray; continue
    }
    [void]$todo.Add($it); $planKB += $it.KB
    Say ('  {0,3}  ' -f $todo.Count) DarkGray -NoNewline
    Say ('{0,-30} ' -f $it.Label) -NoNewline
    Say ('{0,7}' -f (Human $it.KB)) White -NoNewline
    $bt = Get-BackText $it.Back
    if ($it.Back -eq 'gone' -or $it.Back.StartsWith('manual:')) { Say "  $bt" Yellow } else { Say "  $bt" DarkGray }
  }
  if ($script:KeptNote) { Say "  .    $($script:KeptNote)" DarkGray }
  Say ''
  $extra = @(); if ($nClean) { $extra += "$nClean already clean" }; if ($nExcl) { $extra += "$nExcl excluded in config" }
  if ($extra.Count) { Say "($($extra -join ', '))" DarkGray }

  if ($todo.Count -eq 0) { Say 'Nothing to clean.' Green; if (-not $AUTO) { Show-Notes }; exit 0 }
  if ($DRY) { Say "Would free: $(Human $planKB) across $($todo.Count) items. Nothing was deleted." White; Show-Notes; exit 0 }

  if (-not $YES) {
    if (-not $CanAsk) { [Console]::Error.WriteLine('Not running in a terminal, so nothing was deleted. Add --yes to clean without asking.'); exit 2 }
    while ($true) {
      $ans = Read-Answer ("Clean {0} items ({1})? Enter = yes, numbers to skip (e.g. 2 5), n = cancel: " -f $todo.Count, (Human $planKB))
      if ($null -eq $ans) { Say 'Cancelled. Nothing was deleted.'; exit 0 }
      $ans = $ans.Replace(',', ' ').Trim()
      if ($ans -eq '' -or $ans -eq 'y' -or $ans -eq 'yes') { break }
      if ($ans -eq 'n' -or $ans -eq 'no' -or $ans -eq 'q') { Say 'Cancelled. Nothing was deleted.'; exit 0 }
      $nums = @($ans -split '\s+')
      $bad = @($nums | Where-Object { $_ -notmatch '^\d{1,6}$' -or [int]$_ -lt 1 -or [int]$_ -gt $todo.Count })
      if ($bad.Count) { Say "  '$($bad[0])' is not an item number from the list above."; continue }
      foreach ($x in $nums) { $todo[[int]$x - 1].Status = 'skip'; Say "  skipping $($todo[[int]$x - 1].Label)" DarkGray }
      break
    }
  }

  # ---------------------------------------------------------------- clean
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $histRows = New-Object System.Collections.ArrayList
  $failed = 0; $beforeDf = DiskFree
  Say ''
  foreach ($it in $todo) {
    if ($it.Status -ne 'todo') { continue }
    if ($UseColor) { Say ("  ..  {0,-30} {1,7}  removing..." -f $it.Label, (Human $it.KB)) Yellow -NoNewline }
    $ok = $true
    if ($it.Tool -and $it.Run -and (Get-Command $it.Tool -ErrorAction SilentlyContinue)) {
      try { & $it.Run *> $null } catch { $ok = $false }
    } elseif ($it.Paths.Count) {
      foreach ($p in $it.Paths) { Remove-Tree $p }
    } else { $ok = $false }
    if ($it.Paths.Count) { $after = Get-SizeKB $it.Paths; $freed = $it.KB - $after }
    elseif ($ok) { $after = 0; $freed = $it.KB } else { $after = $it.KB; $freed = 0 }
    if ($freed -lt 0) { $freed = 0 }
    $total += $freed
    [void]$histRows.Add(("{0}`t{1}`t{2}`t{3}" -f $now, ($it.Label -replace ' \(\d+\)$', ''), $it.KB, $freed))
    Clear-Progress
    if ($after -gt 0 -and -not $it.Tool) {
      $failed++
      Say '  !   ' Yellow -NoNewline; Say ('{0,-30} {1,7} freed  {2} left: in use or protected' -f $it.Label, (Human $freed), (Human $after))
    } else {
      Say '  OK  ' Green -NoNewline; Say ('{0,-30} {1,7} freed' -f $it.Label, (Human $freed))
    }
  }
  if ($histRows.Count) { New-Item -ItemType Directory -Force -Path $STATE | Out-Null; Add-Content -LiteralPath $HIST -Value $histRows }

  Say ''
  Say "Freed: $(Human $total)" Green
  Say "Disk:  $beforeDf  ->  $(DiskFree)"
  if ($failed) { Say "$failed item(s) were only partly removed; close the apps using them and run clean again." DarkGray }
  if ($DEEP -and @($todo | Where-Object { $_.Back -eq 'build' }).Count) { Say 'Project folders come back with your usual install or build command (npm install, cargo build, dotnet build, ...).' DarkGray }
  if ($AUTO) {
    if ((FreeKB) -lt ([long]$AutoGB * 1048576)) { Notify "Freed $(Human $total), but space is still low. Run clean --review to find large personal files." }
    else { Notify "Freed $(Human $total). $(DiskFree)." }
  } else { Show-Notes }
}
finally {
  if ($Locked) { Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue }
  if ($AUTO) { try { Stop-Transcript | Out-Null } catch { } }
}
exit 0
