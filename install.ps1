# Install cleanspace on Windows (PowerShell):
#   irm https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main/install.ps1 | iex
# Puts cleanspace.ps1 in %LOCALAPPDATA%\cleanspace and the "cleanspace" and "clean" commands in its bin folder,
# which is added to your PATH. No administrator rights needed.
& {   # own scope: "irm | iex" would otherwise leave these variables and settings in your session
  $ErrorActionPreference = 'Stop'
  $raw = 'https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main'
  $dir = Join-Path $env:LOCALAPPDATA 'cleanspace'
  $bin = Join-Path $dir 'bin'
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  $tmp = Join-Path $dir 'cleanspace.ps1.tmp'
  Invoke-WebRequest -UseBasicParsing -Uri "$raw/cleanspace.ps1" -OutFile $tmp
  $errs = $null; [void][Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$null, [ref]$errs)
  if ($errs.Count -or -not (Select-String -LiteralPath $tmp -Pattern '^\$VERSION = ' -Quiet)) {
    Remove-Item $tmp; throw 'download looks broken, nothing installed'
  }
  Move-Item -LiteralPath $tmp -Destination (Join-Path $dir 'cleanspace.ps1') -Force

  # .cmd shims, kept apart from the .ps1 so PowerShell never picks the script directly (that would hit the
  # execution policy). "& exit /b" lets --remove delete the shim while it runs.
  $shim = "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0..\cleanspace.ps1`" %* & exit /b`r`n"
  foreach ($n in 'cleanspace.cmd', 'clean.cmd') { [IO.File]::WriteAllText((Join-Path $bin $n), $shim) }

  # Add bin to the user PATH, reading and writing it unexpanded so entries like %USERPROFILE%\... stay intact.
  $key = Get-Item -LiteralPath 'HKCU:\Environment'
  $path = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
  if (-not (@($path -split ';') -contains $bin)) {
    Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -Type ExpandString `
      -Value ((@($path -split ';' | Where-Object { $_ }) + $bin) -join ';')
  }
  $env:Path = "$env:Path;$bin"

  $v = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'cleanspace.ps1') --version
  Write-Host "OK  $v installed to $dir" -ForegroundColor Green
  Write-Host '    Open a new terminal, then:'
  Write-Host '      clean --dry-run       see what can be freed'
  Write-Host '      clean                 clean (shows the plan and asks first)'
  Write-Host '      clean --schedule      clean automatically when disk space runs low'
}
