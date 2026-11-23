# cleanspace

**Reclaim disk space on macOS, Linux and Windows without losing anything you care about.**

`cleanspace` clears the caches developer tools leave behind: package managers, build tools, editors, Electron apps, browsers and Docker. Before it deletes anything it shows you the plan, what each item costs, and **how each one comes back**. Personal files are never removed without asking you first. It never needs `sudo`.

```text
$ clean
Before: 77Gi free (62% used)

Package managers
    1  pnpm store                        1.0G  re-downloads when needed
    2  Go build/tools                    1.9G  rebuilds itself
Apps
    3  Cursor caches                     1.5G  rebuilds itself
    4  App logs                            4M  permanent
Docker
    5  Docker images & build cache       6.2G  re-downloads when needed

(28 already clean)
Clean 5 items (10.6G)? Enter = yes · numbers to skip, e.g. 2 5 · n = cancel: 5
  skipping Docker images & build cache

  ✓  pnpm store                        1.0G freed
  ...
Freed: 4.4G
Disk:  77Gi free (62% used)  →  81Gi free (60% used)
```

## What makes it different

- **You know what you're giving up.** Every item says whether it *rebuilds itself*, *re-downloads when needed*, *comes back on your next install/build*, or is *permanent*.
- **It cleans on its own when your disk runs low.** `clean --schedule` checks daily and only cleans when free space drops below a limit (20 GB by default), then sends a desktop notification.
- **It shows what keeps filling your disk.** `clean --stats` reports total space freed and which caches grow back fastest, for example `npm cache  2.0G/week`.
- **It leaves your current work alone.** Build folders of projects you edited in the last 14 days are kept, and so are build folders committed to git. Caches of running browsers and Xcode are skipped.
- **Docker without data loss.** Unused images and build cache are removed. Containers (stopped ones too) and volumes are kept, unlike `docker system prune`.

See [docs/RESEARCH.md](docs/RESEARCH.md) for how this compares to Mole, kondo, npkill, CleanMyMac and others, and [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for the full requirements.

## Installation

**macOS and Linux** (also WSL):

```bash
curl -fsSL https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main/install.sh | bash
```

The installer downloads `cleanspace` to `~/.local/bin` and checks it, then adds a `clean` alias (plus `~/.local/bin` to your `PATH` if needed) to `~/.zshrc`, `~/.bashrc` or `~/.bash_profile`.

**Windows 10/11** (in PowerShell, no administrator rights needed):

```powershell
irm https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main/install.ps1 | iex
```

The installer puts `cleanspace.ps1` in `%LOCALAPPDATA%\cleanspace`, and the `cleanspace` and `clean` commands in its `bin` folder, which it adds to your user `PATH`. The commands work from PowerShell, cmd and Windows Terminal, whatever your execution policy.

Open a new terminal and run `clean --dry-run`. The commands and options are the same on every platform.

| Platform | Script | Needs |
| --- | --- | --- |
| macOS | `cleanspace` (Bash) | Bash 3.2+ (the built-in one is fine), `curl` |
| Linux, WSL | `cleanspace` (Bash) | Bash, `curl` |
| Windows 10/11 | `cleanspace.ps1` (PowerShell) | Windows PowerShell 5.1 (built in) or PowerShell 7 |

No platform needs root or administrator rights.

## Usage

| Command | What it does |
| --- | --- |
| `clean` | Scans, shows the plan, asks once, then clears safe caches. |
| `clean --dry-run` | Shows the plan only. Works with every other option. |
| `clean --yes` | Cleans without asking. Required when not run from a terminal (scripts, CI). |
| `clean --deep [dir]` | Also browser caches, caches idle for a week, the Trash, and project build folders under `dir` (default: your code folders). |
| `clean --deep --older 0` | Include build folders of projects edited recently (default: keep the last 14 days). |
| `clean --review` | Goes through personal space hogs one at a time and asks `y/N` for each. |
| `clean --stats` | Space freed so far, biggest wins, what grows back fastest. |
| `clean --schedule [daily\|weekly\|off]` | Clean automatically when free space is low. |
| `cleanspace --config` | Shows the config file, creating it on first use. |
| `cleanspace --update` / `--remove` / `--version` / `--help` | Self-explanatory. `--remove` also removes the schedule, settings and history. |

Exit codes: `0` done, `1` error, `2` confirmation needed (no terminal, use `--yes`), `130` interrupted.

## What gets cleaned

### `clean` (default)

| Category | Items |
| --- | --- |
| Package managers | npm/npx, pnpm, Yarn, Bun, Deno, uv, pip, Pipenv, Poetry (cache only, not virtualenvs), Conda (`conda clean`), Composer, Homebrew (`brew cleanup --prune=all`), Go modules and build cache, Cargo registry, Gradle (caches, daemons, wrapper downloads), Maven wrapper, sbt/Coursier, NuGet, Dart/Flutter pub, CocoaPods, Terraform plugin cache |
| Build and test tools | Playwright, Puppeteer and Cypress browsers, Electron, node-gyp, TypeScript, Prisma engines, pre-commit envs, old JetBrains IDE caches (newest per IDE kept) |
| Xcode (macOS) | DerivedData (skipped while Xcode runs), documentation cache, device logs, simulator caches, old DeviceSupport (newest 2 kept), unavailable simulators |
| Editors and apps | Cursor caches, Electron app caches (Slack, Discord, VS Code, Postman, ...), classic Teams cache, old Claude Code and Cursor Agent versions, app logs, app updater leftovers (ShipIt, Sparkle), downloaded iPhone/iPad update files |
| Docker | Unused images and build cache. Containers and volumes are kept. If Docker Desktop keeps more than 5 GB of build cache between cleans (its default is 20 GB), `clean` offers to cap it at 5 GB in `~/.docker/daemon.json`. |
| Linux only | Thumbnail cache |

### `clean --deep`

Everything above, plus:

| Category | Items |
| --- | --- |
| Browser caches | Arc, Chrome, Chromium, Brave, Edge, Firefox, Safari, Vivaldi: the disk cache only, and only while the browser is closed. On macOS, `clean` offers to quit a running browser holding over 100 MB of cache and reopens it afterwards (your tabs come back). |
| Browser AI models | The on-device model Chrome and Arc download (about 2.7 GB) |
| Idle app caches | Cache folders no other rule covers that haven't changed in 7 days, plus Adobe media caches idle for 7 days. Apple's own caches are never touched. |
| Trash | `~/.Trash` (macOS), `~/.local/share/Trash` (Linux) |
| Project build folders | See the table below. Each is removed only when the project file that owns it sits next to it. |

| Ecosystem | Folders | Must sit next to |
| --- | --- | --- |
| JavaScript | `node_modules`, `.next`, `.nuxt`, `.svelte-kit`, `.angular`, `.astro`, `.expo`, `.metro`, `.turbo`, `.parcel-cache` | `package.json` |
| Rust, Maven, sbt | `target`, `.xwin-cache` | `Cargo.toml`, `pom.xml` or `build.sbt` |
| Gradle, CMake, Flutter | `build`, `.gradle`, `cmake-build-*` | `build.gradle*`, `CMakeLists.txt` or `pubspec.yaml` |
| .NET | `bin`, `obj` | `*.csproj`, `*.fsproj` or `*.vbproj` |
| Unity / Unreal / Godot | `Library`, `Temp` / `Binaries`, `Intermediate`, `DerivedDataCache` / `.godot` | `Assembly-CSharp.csproj` / `*.uproject` / `project.godot` |
| Swift, Dart, Zig | `.build` / `.dart_tool` / `.zig-cache`, `zig-cache`, `zig-out` | `Package.swift` / `pubspec.yaml` / `build.zig` |
| Elixir, Haskell, Elm | `_build`, `.elixir_ls`, `.elixir-tools`, `.lexical` / `.stack-work`, `dist-newstyle` / `elm-stuff` | `mix.exs` / `stack.yaml` or `*.cabal` / `elm.json` |
| PHP, CocoaPods, Terraform, Pixi | `vendor` / `Pods` / `.terraform` / `.pixi` | `composer.json` / `Podfile` / `.terraform.lock.hcl` / `pixi.toml` |
| Python virtualenvs | `.venv`, `venv` (only real virtualenvs, with `pyvenv.cfg` inside) | `pyproject.toml`, `requirements.txt`, `Pipfile` or `setup.py` |
| Python caches | `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`, `.nox`, `__pypackages__` | nothing (always safe) |

Code folders searched: the folder you pass, or `deep_dir` from the config, or whichever of `~/Desktop ~/Documents ~/Developer ~/code ~/dev ~/projects ~/src ~/repos ~/work` exist.

### Windows

The same tiers, with Windows locations:

| Category | Items |
| --- | --- |
| Package managers | npm, pnpm, Yarn, Bun, Deno, uv, pip, Pipenv, Poetry, Conda, Composer, Go, Cargo, Gradle, Maven wrapper, sbt/Coursier, NuGet, Dart/Flutter pub, Scoop and Chocolatey downloads, Terraform, vcpkg |
| Build and test tools | Playwright, Puppeteer, Cypress, Electron, node-gyp, TypeScript, Prisma, pre-commit, old JetBrains caches, Visual Studio installer cache |
| Windows | Temp files untouched for 2+ days, crash dumps and error reports, DirectX/NVIDIA/AMD/Intel shader caches, Internet cache |
| Apps | Cursor, Electron app caches (Slack, Discord, VS Code, Teams, ...), old Claude Code versions |
| `--deep` | Chrome, Edge, Brave, Vivaldi and Firefox caches (per profile; profiles untouched), Chrome AI model, the Recycle Bin on the system drive, project build folders |
| `--review` | Downloads and large old files (to the Recycle Bin), nvm-windows versions, iPhone backups, Hugging Face models, Android emulators |
| Reported only | WSL and Docker virtual disks (`ext4.vhdx`), with the command to shrink them |

Deletion never follows junctions or symbolic links, so a `node_modules` made by pnpm or `npm link` can't take your source code with it. The schedule uses Task Scheduler for your user only.

### `clean --review`

Interactive. Nothing is removed unless you answer `y`.

| Item | Action on `y` |
| --- | --- |
| Entries in `~/Downloads` over 100 MB, largest first | Moved to the Trash |
| Files over 1 GB untouched for 6 months (outside hidden folders, `~/Library` and app bundles) | Moved to the Trash |
| Node versions installed with nvm (the one in use is skipped, the default is labelled) | Deleted |
| Intel Homebrew in `/usr/local` on Apple Silicon | Removed with [Homebrew's official uninstaller](https://github.com/Homebrew/install#uninstall-homebrew) |
| iOS device backups, Xcode archives, Hugging Face models, Android emulators | Deleted |

## Automatic cleaning

```bash
clean --schedule          # check daily at 11:00; clean only if free space < 20 GB
clean --schedule weekly   # check on Mondays
clean --schedule off
```

macOS uses a launchd agent (a run missed during sleep happens on wake). Linux uses a systemd user timer, or cron if systemd isn't available. Scheduled runs only clean the default tier, never `--deep` or `--review` items, and run at low priority. Output goes to `~/.local/state/cleanspace/auto.log`. macOS doesn't let launchd jobs read `~/Desktop`, `~/Documents`, `~/Downloads` or iCloud Drive, so if your script lives there (a dev checkout), the schedule runs a copy in `~/.local/state/cleanspace/`, which every manual run keeps up to date. A notification tells you what was freed, and suggests `clean --review` if space is still low.

## Configuration

`cleanspace --config` creates `~/.config/cleanspace/config`:

```ini
exclude = Docker images & build cache          # an item name from the plan
exclude = ~/Library/Caches/com.spotify.client  # or a path; * wildcards work
deep_dir = ~/code                              # where --deep looks for projects (repeatable)
older_days = 14                                # keep builds of projects edited this recently
auto_below_gb = 20                             # the schedule cleans below this much free space
```

## Safety

The safety rules are adapted from [Mole](https://github.com/tw93/Mole) and [kondo](https://github.com/tbillington/kondo), with additions.

- **Plan first.** Nothing is deleted before you've seen the list and agreed. Without a terminal, `--yes` is required.
- **Personal data is never removed automatically.** It only appears in `--review`, one item at a time.
- **Browser profiles are untouched.** History, passwords, cookies and bookmarks stay, and you stay signed in.
- **Running apps are skipped.** Browser caches and Xcode DerivedData are only cleared while the app is closed. On macOS, `clean` can quit the app for you, but only after you answer `y`, and it reopens it afterwards. `--yes` and the schedule never quit anything.
- **Build folders need their project file, must not be committed to git, and must belong to a project you haven't edited in 14 days.** A build folder with a git repo or a `*-keypair.json` inside is kept, so Solana program keys in `target/deploy` are safe. Hidden folders are never searched.
- **Nothing in use is pulled out from under a program.** The npx cache is skipped while anything runs from it, such as an MCP server. The Deno cache keeps `location_data`, which holds app localStorage. `pnpm dlx` tools are kept.
- **Honest about what comes back.** Playwright browsers say *comes back with: npx playwright install*, and the schedule never removes anything that needs a manual reinstall.
- **Caches are recognised, not guessed.** A folder called `Cache` inside an app's support folder only counts when Chromium's marker folders sit next to it.
- **Deletes stay inside your home folder** (plus folders you pass to `--deep`). Symlinks are not followed.
- **No sudo.** One run at a time. Ctrl-C stops cleanly.
- **No telemetry.** History stays on your machine.

## FAQ

**The Trash shows "give your terminal Full Disk Access".**
macOS protects `~/.Trash`. Enable your terminal in System Settings → Privacy & Security → Full Disk Access, or empty the Trash from Finder.

**An item said "N left: in use or protected".**
An app was using those files. Quit it and run `clean` again.

**My free space didn't go up after `--review`.**
Downloads and large files go to the Trash so you can change your mind. Empty it, or run `clean --deep`.

**What is "Intel Homebrew (x86)"?**
On Apple Silicon, Homebrew lives in `/opt/homebrew`. A second copy in `/usr/local` is usually left over from an Intel Mac and runs through Rosetta. `clean --review` lists what is only installed there before offering to remove it.

**Space keeps filling up again.**
Run `clean --stats`: *Fastest to grow back* shows which caches refill quickest, so you know which app to rein in. On macOS, `clean` also reports swap when it's over 2 GB. Swap grows while memory is short and only shrinks on a restart.

**What about system caches on Linux?**
They need root, so they're left to you, for example `sudo apt clean` and `sudo journalctl --vacuum-time=2weeks`.

## Contributing

The tool is one file, [`cleanspace`](cleanspace). To add a cache, add one line to the matching section in `scan()`:

```bash
item "Label"  path [path...]                  # removes the paths
item "Label"  path -- tool clean-command      # runs the tool's own command if installed
GUARD="App"  item "Label" path                # skipped while "App" is running
BACK=gone    item "Label" path                # how it comes back: auto | dl | build | gone
```

Run the tests and the linter before sending a change. CI runs both on macOS (bash 3.2) and Ubuntu:

```bash
tests/run.sh                     # sandboxed: uses a throwaway $HOME and stubbed tools
shellcheck -s bash -S warning cleanspace install.sh tests/run.sh
```

To work on it locally, link your checkout so edits run right away and `--update` uses `git pull`:

```bash
git clone https://github.com/Pantho-Haque/cleanspace.git
ln -sf "$PWD/cleanspace/cleanspace" ~/.local/bin/cleanspace
```
