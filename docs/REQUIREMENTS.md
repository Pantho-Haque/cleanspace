# Requirements

cleanspace 2.1. Each requirement has an ID. "Test" names the check in `tests/run.sh` that covers it,
or says how it is verified.

## Functional requirements

### Scanning and plan

| ID | Requirement | Test |
| --- | --- | --- |
| F1 | Measure every item before deleting anything, and show the plan grouped by section, with sizes. | dry run lists npm |
| F2 | Each item in the plan says how it comes back: rebuilds itself / re-downloads when needed / comes back on your next install or build / permanent. | dry run shows how it comes back |
| F3 | Items that are already empty are hidden and counted ("28 already clean"). | manual |
| F4 | Skipped items show why (app running, tool missing, Full Disk Access needed). | browser cache skipped while browser runs |
| F5 | `--dry-run` shows the plan and deletes nothing, with every mode. | dry run keeps files |

### Confirmation and control

| ID | Requirement | Test |
| --- | --- | --- |
| F6 | In a terminal, ask once: Enter cleans everything, numbers skip items, `n` cancels. Bad input asks again. | skipped item 1 kept, answer n cancels |
| F7 | `--yes` cleans without asking. Without a terminal and without `--yes`, nothing is deleted and the exit code is 2. | non-interactive without --yes exits 2 |
| F8 | Personal data (Downloads, backups, archives, AI models, Node versions, large old files) is never deleted except in `--review`, one item at a time, after `y`. Downloads and large files go to the Trash. | Downloads untouched |
| F9 | Exclusions in the config file match item names or paths, with `*` wildcards. An exclusion inside an item's folder protects the whole item. | excluded label kept |

### What gets cleaned

| ID | Requirement | Test |
| --- | --- | --- |
| F10 | Default tier: package manager, build tool, editor, Electron app and Docker caches that the owning tool rebuilds or re-downloads. | --yes removes npm/pip cache |
| F11 | Use a tool's own clean command when it is installed (`brew cleanup`, `go clean -modcache`, `uv cache clean`, `conda clean`). | manual |
| F12 | Docker: remove unused images and the build cache only. Containers, stopped ones included, and volumes are kept. | manual (needs Docker) |
| F13 | `--deep` adds browser caches (never profiles), browser AI models, caches idle for 7+ days, the Trash or Recycle Bin, and project build folders for about 20 ecosystems (see README). | stale node_modules removed, .NET bin removed, Unity Library removed |
| F14 | A build folder is removed only if its project file is next to it, it is not inside a hidden folder, it is not tracked by git, and the project had no file edits in `--older` days (default 14). | node_modules without package.json, git-tracked vendor kept, recently edited project kept, hidden folders not searched |
| F15 | Caches of running apps (browsers, Xcode) are skipped. | browser cache kept while browser runs |
| F16 | Old versions are pruned and the current one is kept: Claude Code, Cursor Agent, JetBrains IDE caches, Xcode DeviceSupport (newest 2 kept). | manual |

### Automation and insight

| ID | Requirement | Test |
| --- | --- | --- |
| F17 | `--schedule [daily|weekly|off]` installs a launchd agent (macOS), a systemd user timer, or a cron entry (Linux). | manual |
| F18 | `--auto` (what the schedule runs) cleans the default tier only when free space is below `auto_below_gb` (default 20). It sends a desktop notification, and suggests `--review` if space is still low. | manual |
| F19 | Every real clean is recorded. `--stats` shows total freed, the biggest wins, and how fast each cache grows back per week. | history recorded, --stats shows total |

### Lifecycle

| ID | Requirement | Test |
| --- | --- | --- |
| F20 | `--config` creates a commented config file and shows the active settings. Bad lines warn and are ignored. | --config creates file, bad config line warns |
| F21 | `--update` downloads, checks syntax and version, then atomically replaces the script. A git checkout updates with `git pull`. | manual |
| F22 | `--remove` deletes the script, schedule, config, history and the shell-rc lines, and leaves the rest of the rc file alone. | --remove tests |
| F23 | `--version`, `--help`. Unknown options exit 1. | --version, unknown option exits 1 |

## Non-functional requirements

| ID | Requirement | How |
| --- | --- | --- |
| N1 | **Safety:** never delete outside `$HOME`, the cache/config dirs, or folders passed to `--deep`. Never `/` or `$HOME` itself, or paths with `..`. | `safe_path`. Test: symlink target survives |
| N2 | **No root:** never calls `sudo`. The only password prompt is Homebrew's own uninstaller in `--review`, after you agree. | code review |
| N3 | **No surprise data loss:** browser profiles, cookies, Docker volumes, containers, Maven's local repo, Poetry virtualenvs and Apple's own caches are never touched. | code review |
| N4 | **Concurrency:** one run at a time (lock with PID). A stale lock from a crashed run is taken over. | lock tests |
| N5 | **Interrupts:** Ctrl-C stops the current deletion, reports what was freed so far, records it, and exits 130. | manual |
| N6 | **Portability:** macOS (bash 3.2, BSD tools), Linux and WSL (GNU tools) via `cleanspace`, and Windows 10/11 via `cleanspace.ps1` (Windows PowerShell 5.1 or PowerShell 7). Same options, output and config format everywhere. No dependencies beyond a standard system. | CI on macos-latest (system bash 3.2), ubuntu-latest and windows-latest (PowerShell 5.1 and 7) |
| N14 | **Windows deletion safety:** never follow junctions or symbolic links when measuring or deleting (pnpm and `npm link` use them). Locked files are skipped, not fatal. | tests/run.ps1: junction target survives |
| N7 | **Speed:** a default scan finishes in under 30 s on a typical developer laptop. `--deep` cost grows with the size of the code folders. | measured: 16 s default, 18 s deep on the dev machine |
| N8 | **Accessibility and output:** honours `NO_COLOR` and `TERM=dumb`. No color, spinners or progress lines when output isn't a terminal, so logs stay clean. Plain-language messages. | code review |
| N9 | **Exit codes:** 0 done, 1 error, 2 needs `--yes`, 130 interrupted. | tests |
| N10 | **Quality gates:** shellcheck clean at warning level, the test suite passes on both OSes in CI. | `.github/workflows/ci.yml` |
| N11 | **Self-contained:** one file, installable with `curl`, upgradable in place without breaking a running copy (atomic `mv`). | install.sh |
| N12 | **Privacy:** no telemetry. History stays in `~/.local/state/cleanspace`. | code review |
| N13 | **Scheduled runs are polite:** low CPU and IO priority, logs trimmed to about 1 MB, missed runs catch up after sleep (launchd, `Persistent=true`). | schedule() |
