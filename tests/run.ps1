# Tests for cleanspace.ps1 (Windows). Every test runs against a throwaway profile (USERPROFILE, LOCALAPPDATA,
# APPDATA and TEMP point into a temp folder) with docker stubbed out, so nothing real is touched.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1
$CS = Join-Path (Split-Path $PSScriptRoot) 'cleanspace.ps1'
$script:pass = 0; $script:fail = 0; $script:OUT = ''
$realTemp = [IO.Path]::GetTempPath()
$exe = 'powershell.exe'; if ($PSVersionTable.PSEdition -eq 'Core') { $exe = 'pwsh' }   # test the edition running the tests

function New-Home {
  $script:H = Join-Path $realTemp ("cs-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $script:L = "$H\AppData\Local"; $script:A = "$H\AppData\Roaming"
  New-Item -ItemType Directory -Force -Path $L, $A, "$L\Temp", "$H\stub" | Out-Null
  Set-Content -Path "$H\stub\docker.cmd" -Value '@exit /b 1'
}
function CS {
  $env:USERPROFILE = $H; $env:LOCALAPPDATA = $L; $env:APPDATA = $A; $env:TEMP = "$L\Temp"; $env:TMP = "$L\Temp"
  $env:Path = "$H\stub;" + $script:basePath
  $script:OUT = (& $exe -NoProfile -ExecutionPolicy Bypass -File $CS @args 2>&1 | Out-String)
  $script:RC = $LASTEXITCODE
  $env:CLEANSPACE_INPUT = $null
}
function Mk([string]$p, [int]$bytes = 20000) {
  New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
  [IO.File]::WriteAllBytes($p, (New-Object byte[] $bytes))
}
function Old([string]$dir) {   # make everything under $dir look untouched for years
  Get-ChildItem -LiteralPath $dir -Recurse -Force | ForEach-Object { $_.LastWriteTime = [datetime]'2020-01-01' }
  (Get-Item -LiteralPath $dir).LastWriteTime = [datetime]'2020-01-01'
}
function Check([string]$name, [bool]$cond) {
  if ($cond) { $script:pass++; "ok   $name" }
  else { $script:fail++; "FAIL $name"; ($script:OUT -split "`n" | ForEach-Object { "     | $_" }) }
}
function Has([string]$s) { $script:OUT -like "*$s*" }
$script:basePath = $env:Path
$savedEnv = @{ USERPROFILE = $env:USERPROFILE; LOCALAPPDATA = $env:LOCALAPPDATA; APPDATA = $env:APPDATA; TEMP = $env:TEMP; TMP = $env:TMP }

# ---- basics
New-Home
CS --version; Check '--version' (Has 'cleanspace 2')
CS --help; Check '--help lists options' (Has '--schedule')
CS --bogus; Check 'unknown option exits 1' ($RC -eq 1 -and (Has 'unknown option'))
CS --older abc; Check '--older validates' ($RC -eq 1 -and (Has 'needs a number'))

# ---- dry run deletes nothing
Mk "$L\npm-cache\_cacache\blob"
Mk "$L\pip\Cache\http\x"
CS --dry-run
Check 'dry run exit 0' ($RC -eq 0)
Check 'dry run lists npm' (Has 'npm cache')
Check 'dry run shows how it comes back' (Has 're-downloads when needed')
Check 'dry run keeps files' (Test-Path "$L\npm-cache\_cacache\blob")

# ---- no terminal and no --yes: refuse
CS
Check 'non-interactive without --yes exits 2' ($RC -eq 2)
Check 'non-interactive without --yes keeps files' (Test-Path "$L\npm-cache\_cacache\blob")

# ---- --yes cleans caches, keeps personal data and exclusions
Mk "$H\Downloads\movie.mp4"
Mk "$L\Composer\repo\x"
New-Item -ItemType Directory -Force -Path "$A\cleanspace" | Out-Null
Set-Content -Path "$A\cleanspace\config" -Value 'exclude = composer cache'
CS --yes
Check '--yes exit 0' ($RC -eq 0)
Check '--yes removes npm cache' (-not (Test-Path "$L\npm-cache\_cacache"))
Check '--yes removes pip cache' (-not (Test-Path "$L\pip\Cache"))
Check 'Downloads untouched' (Test-Path "$H\Downloads\movie.mp4")
Check 'excluded label kept' (Test-Path "$L\Composer\repo\x")
Check 'lock released' (-not (Test-Path "$L\cleanspace\state\lock"))
Check 'history recorded' ((Get-Content "$L\cleanspace\state\history.tsv" -Raw) -like '*npm cache*')
CS --stats; Check '--stats shows total' (Has 'Freed')

# ---- junctions are never followed (pnpm and npm link use them)
Mk "$H\precious\work.txt"
New-Item -ItemType Directory -Force -Path "$L\npm-cache\_cacache" | Out-Null
Mk "$L\npm-cache\_cacache\real"
New-Item -ItemType Junction -Path "$L\npm-cache\_cacache\link" -Target "$H\precious" | Out-Null
CS --yes
Check 'junction target survives' (Test-Path "$H\precious\work.txt")
Check 'cache next to the junction removed' (-not (Test-Path "$L\npm-cache\_cacache\real"))

# ---- interactive selection: skip item 1
New-Home
Mk "$L\npm-cache\_cacache\blob"; Mk "$L\pip\Cache\http\x"
Set-Content -Path "$H\answers" -Value '1'
$env:CLEANSPACE_INPUT = "$H\answers"; CS
Check 'skipped item 1 (npm) kept' (Test-Path "$L\npm-cache\_cacache\blob")
Check 'item 2 (pip) cleaned' (-not (Test-Path "$L\pip\Cache"))
Mk "$L\pip\Cache\http\x"; Set-Content -Path "$H\answers" -Value 'n'
$env:CLEANSPACE_INPUT = "$H\answers"; CS
Check 'answer n cancels' (Test-Path "$L\pip\Cache\http\x")

# ---- concurrent runs are refused
New-Home
New-Item -ItemType Directory -Force -Path "$L\cleanspace\state" | Out-Null
Set-Content -Path "$L\cleanspace\state\lock" -Value $PID
CS --yes; Check 'second run refused while locked' ($RC -eq 1 -and (Has 'already running'))
Set-Content -Path "$L\cleanspace\state\lock" -Value 999999
CS --yes; Check 'stale lock is taken over' ($RC -eq 0)

# ---- --deep project builds
New-Home
$P = "$H\code"
Mk "$P\old\package.json" 10;   Mk "$P\old\node_modules\a\index.js"
Mk "$P\fresh\package.json" 10; Mk "$P\fresh\node_modules\a\index.js"
Mk "$P\orphan\node_modules\a\x"
Mk "$P\rand\target\x"
Mk "$P\php\composer.json" 10;  Mk "$P\php\vendor\lib\x"
Mk "$P\net\app.csproj" 10;     Mk "$P\net\bin\Debug\app.dll"
Mk "$P\docs\build\index.html"
Mk "$P\py\app.py" 10;          Mk "$P\py\__pycache__\app.pyc"
Mk "$P\pyproj\pyproject.toml" 10; Mk "$P\pyproj\.venv\pyvenv.cfg" 10; Mk "$P\pyproj\.venv\lib\x"
Mk "$P\novenv\pyproject.toml" 10; Mk "$P\novenv\.venv\notes.txt"          # called .venv but not a virtualenv
Push-Location "$P\php"; git init -q; git add -f vendor composer.json; git -c user.email=t@t -c user.name=t commit -qm init; Pop-Location
foreach ($d in 'old', 'orphan', 'rand', 'php', 'net', 'docs', 'py', 'pyproj', 'novenv') { Old "$P\$d" }
New-Item -ItemType Directory -Force -Path "$A\cleanspace" | Out-Null
Set-Content -Path "$A\cleanspace\config" -Value 'exclude = Recycle Bin'   # the bin is real even in a fake profile
CS --deep $P --yes
Check 'stale node_modules removed'        (-not (Test-Path "$P\old\node_modules"))
Check 'recently edited project kept'      (Test-Path "$P\fresh\node_modules")
Check 'node_modules without package.json' (Test-Path "$P\orphan\node_modules")
Check 'random target folder kept'         (Test-Path "$P\rand\target")
Check 'git-tracked vendor kept'           (Test-Path "$P\php\vendor\lib\x")
Check '.NET bin removed'                  (-not (Test-Path "$P\net\bin"))
Check 'plain build folder kept'           (Test-Path "$P\docs\build\index.html")
Check '__pycache__ removed'               (-not (Test-Path "$P\py\__pycache__"))
Check 'virtualenv removed'                (-not (Test-Path "$P\pyproj\.venv"))
Check '.venv that is not a virtualenv kept' (Test-Path "$P\novenv\.venv\notes.txt")
Check 'kept projects are reported'        (Has 'edited in the last 14 days')
CS --deep $P --older 0 --yes
Check '--older 0 includes recent projects' (-not (Test-Path "$P\fresh\node_modules"))

# ---- rules learned from Mole's source
New-Home
Mk "$L\npm-cache\_npx\abc\node_modules\x\index.js"
$sleeper = Start-Process -PassThru -WindowStyle Hidden $exe -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120 # npm-cache\_npx'
Mk "$L\deno\location_data\x\local_storage"; Mk "$L\deno\deps\https\x"
Mk "$A\NotElectron\Cache\data.db"
Mk "$A\Slack\Code Cache\js\x"; Mk "$A\Slack\Cache\x"
Mk "$H\.vscode\extensions\pub.ext-1.0.0\package.json"; Mk "$H\.vscode\extensions\pub.ext-2.0.0\package.json"
Set-Content -Path "$H\.vscode\extensions\.obsolete" -Value '{"pub.ext-1.0.0":true}'
CS --yes
Stop-Process -Id $sleeper.Id -ErrorAction SilentlyContinue
Check 'npx cache kept while in use'        (Test-Path "$L\npm-cache\_npx\abc\node_modules\x\index.js")
Check 'Deno localStorage kept'             (Test-Path "$L\deno\location_data\x\local_storage")
Check 'Deno deps removed'                  (-not (Test-Path "$L\deno\deps"))
Check 'Cache without Chromium marker kept' (Test-Path "$A\NotElectron\Cache\data.db")
Check 'Electron app Cache removed'         (-not (Test-Path "$A\Slack\Cache"))
Check 'obsolete extension removed'         (-not (Test-Path "$H\.vscode\extensions\pub.ext-1.0.0"))
Check 'current extension kept'             (Test-Path "$H\.vscode\extensions\pub.ext-2.0.0")

New-Home
$P = "$H\code"
Mk "$P\sol\Cargo.toml" 10; Mk "$P\sol\target\deploy\prog-keypair.json"; Mk "$P\sol\target\debug\x"
Old $P
New-Item -ItemType Directory -Force -Path "$A\cleanspace" | Out-Null
Set-Content -Path "$A\cleanspace\config" -Value 'exclude = Recycle Bin'
CS --deep $P --yes
Check 'target with a keypair kept' (Test-Path "$P\sol\target\deploy\prog-keypair.json")

# ---- a TEMP that points at the profile itself is not trusted
New-Home
Mk "$H\Documents\thesis.docx"; Old "$H\Documents"
$env:USERPROFILE = $H; $env:LOCALAPPDATA = $L; $env:APPDATA = $A; $env:TEMP = $H; $env:TMP = $H   # this profile, with TEMP = the profile
$script:OUT = (& $exe -NoProfile -ExecutionPolicy Bypass -File $CS --yes 2>&1 | Out-String)
Check 'TEMP=profile does not delete documents' (Test-Path "$H\Documents\thesis.docx")

# ---- config file
New-Home
CS --config; Check '--config creates file' (Test-Path "$A\cleanspace\config")
Add-Content -Path "$A\cleanspace\config" -Value 'bogus line'
CS --dry-run; Check 'bad config line warns' (Has 'ignoring')

foreach ($k in $savedEnv.Keys) { Set-Item "env:$k" $savedEnv[$k] }
$env:Path = $script:basePath
Get-ChildItem $realTemp -Directory -Filter 'cs-test-*' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
""; "$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
