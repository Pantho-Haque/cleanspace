# Market research

Research done November 2026 to decide what cleanspace 2.0 should do. Facts about other tools come from
their READMEs. Where something could not be confirmed it says so. Claims that "no tool does X" mean we
looked and did not find one, not that one cannot exist.

## The field

| Tool | Type | What it cleans | Safety model | Gaps for developers |
| --- | --- | --- | --- | --- |
| [Mole](https://github.com/tw93/mole) (`mo`) | macOS CLI/TUI | System and app caches, logs, Xcode, Homebrew, app uninstall, project build folders (`mo purge`) | `--dry-run` on every destructive command, persistent whitelist (`~/.config/mole/whitelist`) | macOS only. No scheduling, no history. |
| [kondo](https://github.com/tbillington/kondo) | CLI + GUI | Build folders across about 20 ecosystems | Asks per project. Has an age filter | Build folders only. No global caches. |
| [npkill](https://github.com/voidcosmos/npkill) | TUI | `node_modules` only | Pick folders by hand | One ecosystem |
| [cargo-sweep](https://github.com/holmgr/cargo-sweep) | CLI | Rust `target/` | Dry run, age filter | One ecosystem |
| [DevCleaner for Xcode](https://github.com/vashpan/xcode-dev-cleaner) | macOS GUI | Xcode DerivedData, DeviceSupport, archives | Checkbox list | Xcode only |
| [mac-cleanup-sh / -py](https://github.com/mac-cleanup/mac-cleanup-py) | macOS CLI | Brew, Xcode, Docker, Composer, caches, Trash | Confirmation, dry run in the Python version (unverified) | Uses `sudo`, removes broadly |
| [BleachBit](https://www.bleachbit.org/) | Linux/Windows GUI+CLI | App caches, logs, browser data, cookies | `--preview` | Deletes cookies and history, so users get signed out. Some cleaners need root. |
| ncdu, dua-cli, gdu, DaisyDisk, GrandPerspective | Disk analyzers | Anything the user picks | Manual | Show where the space went but don't know what is safe |
| CleanMyMac (MacPaw) | macOS GUI, paid subscription | System junk, caches, mail attachments, Trash | Review list, exclusion list, background low-space alerts | Closed source, subscription, distrusted by many developers |
| Pretty Clean, Stacer, KDE Sweeper | GUIs | General and app caches | Checkboxes | Not aimed at developer tooling |

## What users are afraid of

Gathered from the issue trackers and READMEs above. The research agent's specific Reddit and HN links could not be verified, so they are left out.

1. **Losing something that cannot come back.** This is the main reason developers avoid cleaners. Tools rarely say whether an item will re-download, rebuild itself, or is gone for good.
2. **Getting signed out.** Cleaners that clear cookies or browser profiles (BleachBit's browser cleaners, for example) log people out everywhere.
3. **Breaking the machine.** Anything that needs `sudo` or touches system folders can break an install.
4. **Breaking current work.** Deleting `node_modules` or `target` in the project you're working on means a long reinstall or rebuild in the middle of the day.
5. **Not knowing what will happen.** "Clean everything?" with no list, or a list with no sizes.
6. **Running out of space again a week later.** Cleaning is a chore people forget until the disk is full.

## Gaps cleanspace 2.0 fills

| Idea | Who already does it | Decision |
| --- | --- | --- |
| Show, for every item, how it comes back: *rebuilds itself*, *re-downloads when needed*, *comes back on your next install/build*, or *permanent* | Not found in any tool | **Built.** It is the direct answer to fear #1. |
| Plan first, then one confirmation where you can skip items by number | Mole and kondo ask per category or project. npkill and DevCleaner make you pick each one | **Built.** You see everything, sizes included, and answer once. |
| Clean automatically, but **only when free space is low**, using the system scheduler (launchd or systemd) and a desktop notification | CleanMyMac alerts on low space but doesn't clean. No open-source CLI found | **Built** (`--schedule`, `--auto`). Answers fear #6. |
| Track how fast each cache grows back between cleans | Not found | **Built** (`--stats`). It tells you which tool is filling your disk. |
| Lifetime "space freed" total | Rare | **Built** (`--stats`). |
| Keep build folders of projects edited recently | kondo and cargo-sweep have age filters, but you have to ask for them | **Built, on by default** (14 days), across all ecosystems. |
| Never delete a build folder that is committed to git | Not found | **Built.** A committed `vendor/` or `Pods/` stays. |
| Skip a cache while its app is running | Mole is partly verified. Most scripts don't | **Built** for browsers and Xcode. |
| Docker cleanup that keeps stopped containers | Most tools run `docker system prune`, which deletes stopped containers and any data inside them | **Built.** Only unused images and the build cache are removed. |
| Clean caches no other rule covers, but only ones idle for a week | CleanMyMac clears user caches broadly | **Built** in `--deep`. Apple's own caches are never touched. |
| Exclusion list | Mole, CleanMyMac, BleachBit | **Built** (`cleanspace --config`). |
| Undo / quarantine | Trash-based tools only | Personal files go to the Trash (`--review`). Caches don't, because keeping them would defeat the point. |
| Duplicate finder, disk map | czkawka, DaisyDisk, ncdu | **Not built.** Those tools do it well, and it isn't cleaning. `--review` lists large files you haven't touched in 6 months. |
| GUI | CleanMyMac, Pretty Clean | **Not built.** The audience lives in the terminal. |
| Windows | kondo, BleachBit | **Not built.** Different cache layout and no Bash. Can be revisited. |

## How cleanspace is positioned

> The only cleaner that tells you how everything it deletes comes back, never needs sudo, and cleans
> on its own when your disk runs low, without touching personal files.

## What competitors actually delete (read from their source, November 2026)

We read each tool's source code, not its README, and compared every path with cleanspace. Each target was
either adopted or rejected for a stated reason.

### kondo (tbillington/kondo, `kondo-lib/src/lib.rs`)

Project build folders, each tied to a project file. **Adopted:** `.metro`, `.xwin-cache`, `build` (Gradle,
CMake, Flutter), `cmake-build-*`, `bin`/`obj` (.NET), Unity `Library`/`Temp`, Unreal
`Binaries`/`Intermediate`/`DerivedDataCache`, `.godot`, `.terraform`, `.pixi`, `dist-newstyle` (Cabal), `zig-out`,
the Elixir language-server folders, `.nox`, `__pypackages__`, and `target` for sbt.
**Rejected:** Unity `Build(s)`/`Logs` and Unreal `Saved` (they hold your builds, logs and save games),
`.ipynb_checkpoints` (notebook backups), `.swiftpm` (holds Xcode schemes).

### mac-cleaner (sp3esu, Go)

Deletes with `os.RemoveAll` after a home-only path check, with no age gate and no running-app check. It wipes all of
`~/Library/Caches/*`, whole Figma and Zoom data folders, and `venv`/`.venv`. **Adopted:** Safari cache (guarded),
Adobe media caches (only when idle for 7 days), classic Teams cache, downloaded iPhone/iPad update files,
Gradle `build` folders. **Rejected:** the blanket cache wipe (we only take caches idle for 7 days), Figma and Zoom
data (sign-ins, sessions), virtualenvs (can't always be rebuilt), `git gc --aggressive` (not a cache),
Photos analysis caches (Apple's; we never touch Apple's caches).

### mac-cleaner-cli (guhcostan, TypeScript) and mac-cleanup-cli (gitchrisqueen, Python)

Almost entirely a subset of cleanspace. **Adopted:** app updater leftovers (`*.ShipIt`, Sparkle), the XDG pip cache on
macOS. **Rejected:** `/tmp` and `$TMPDIR` without an age gate, `docker container prune` (stopped containers can hold
data), simulator runtimes (multi-GB re-download), Xcode archives (shipped builds and dSYMs), orphan LaunchAgents
(configuration, not cache), stripping `.lproj` from apps (breaks code signatures). The Python tool's "blocked while
Chrome runs" metadata is declared but never enforced. cleanspace enforces its guards.

### Mole (tw93/Mole, `lib/clean/*.sh`, `lib/core/*.sh`)

The most careful of the tools: about 640 targets, a hard-coded protection list, and per-path guards. Besides new
targets, reading it changed how cleanspace behaves:

- **npx cache:** skipped while any program runs from it. MCP servers do.
- **Playwright browsers:** they don't come back on their own. They're labelled *comes back with: npx playwright install*,
  and the schedule leaves them.
- **pnpm:** uses `pnpm store prune` instead of deleting the store, and keeps `pnpm dlx`.
- **Deno:** cleans `deps`, `npm`, `gen` and `remote` only. `location_data` is app localStorage.
- **Build folders:** a folder with a nested `.git` or a `*-keypair.json` is kept (Solana/Anchor program keys).
- **Electron caches:** a plain `Cache` folder only counts when a Chromium marker folder sits next to it.
- **Idle-cache sweep:** now skips Mole's protected names (password managers, licence stores, Surge, DisplayLink,
  llama.cpp, R, kitty, tealdeer, ...).

**Adopted targets:** Corepack, mise, rustup, pyenv, Ruby, Hex and opam download caches, Expo caches, the Android build
cache, global ruff/mypy caches, PyInstaller, Lima/Vagrant downloads, gh/kubectl caches, Cloud CLI logs, obsolete VS
Code/Cursor extensions (only those listed in `.obsolete`), the Xcode cache and IB Support, XCTest device clones, old
Claude Desktop Claude Code builds, old JetBrains Toolbox builds (newest 2 kept), crash reports older than 30 days,
Chrome updater downloads, SentryCrash/KSCrash, the Steam caches, Zed, editor logs, more Teams leaves, Chromium profile
cache leaves for Chrome, Chromium, Brave, Edge, Arc and Vivaldi, and the project folders `.output`, `coverage`, `DerivedData`,
`.cxx` and `.terragrunt-cache`.

**Rejected:**
- Apple daemon caches (photoanalysisd, iconservices, ...): Apple's, and rebuilding costs CPU.
- Per-device simulator internals: too fiddly for the space.
- Wallpaper render bitmaps: inside another app's container, so reading them prompts for access.
- Bazel: slow to rebuild.
- `venv`/`.venv` and generic `dist`: may hold your own work.
- About 40 single-app caches for niche apps: the idle-cache sweep catches most of them anyway.

**Where we still differ on purpose:**
- **Gradle `caches/` and NuGet packages:** we delete them. The plan says they *re-download when needed*, and you can skip them by number.
- **Docker:** we prune unused images. Mole only reports them.
