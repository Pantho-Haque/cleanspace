# cleanspace

**Reclaim disk space on macOS and Linux without losing anything you care about.**

`cleanspace` is a single Bash script that clears the caches developer tools leave behind: package managers, build tools, editors, Electron apps, browsers and Docker. Everything it deletes rebuilds itself on demand. Personal files are never removed without your explicit confirmation.

```text
$ clean --dry-run
Before: 80Gi free (61% used)  (dry run, nothing is deleted)

Package managers
  ○  npm cache                       757M would be freed
  ○  pnpm store                       52M would be freed
Apps
  ○  Cursor caches                   2.6G would be freed
  ○  Electron app caches             533M would be freed
  ○  Old Claude Code versions        825M would be freed
...
Worth a look yourself  (never deleted here; run cleanspace --review to go through them)
  ·  Downloads                      12.0G  ~/Downloads
  ·  Intel Homebrew (x86)            3.1G  /usr/local/Homebrew

Total that would be freed: 8.1G  (Docker counted separately)
```

## Contents

- [Installation](#installation)
- [Usage](#usage)
- [What gets cleaned](#what-gets-cleaned)
- [Safety](#safety)
- [Updating and uninstalling](#updating-and-uninstalling)
- [FAQ](#faq)
- [Contributing](#contributing)

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main/install.sh | bash
```

The installer:

1. Checks that you are on macOS or Linux.
2. Downloads `cleanspace` to `~/.local/bin`.
3. Adds a `clean` alias, plus `~/.local/bin` to your `PATH` if it is missing, to your shell's startup file (`~/.zshrc` for zsh, `~/.bashrc` for bash on Linux, `~/.bash_profile` for bash on macOS).

Open a new terminal, or `source` the file it names, and run `clean`.

**Requirements:** macOS or Linux, Bash 3.2 or newer (the version macOS ships is fine), and `curl`. Root access is never needed.

## Usage

| Command | What it does |
| --- | --- |
| `clean` | Clears all safe caches and runs `docker system prune -a`. |
| `clean --dry-run` | Shows what would be freed. Deletes nothing. Combines with `--deep` and `--review`. |
| `clean --deep [dir]` | Also clears browser caches, browser AI models, the Trash, and project build folders under `dir` (default `~/Desktop`). |
| `clean --review` | Goes through personal space hogs one at a time and asks `y/N` before removing each. |
| `cleanspace --update` | Updates to the latest version. |
| `cleanspace --remove` | Uninstalls `cleanspace` and removes the lines the installer added. |
| `cleanspace --help` | Prints the option summary. |

`clean` is an alias for `cleanspace`, so the two names work the same way.

## What gets cleaned

### `clean` (default)

Caches that the owning tool downloads or rebuilds the next time it needs them.

| Category | Items |
| --- | --- |
| Package managers | npm and npx, pnpm, Yarn, Bun, uv, pip, Poetry, Composer, Homebrew (`brew cleanup --prune=all`), Go modules and build cache, Cargo downloads, Gradle, CocoaPods |
| Build and test tools | Playwright and Puppeteer browsers, Electron and electron-builder, node-gyp headers, TypeScript, Prisma engines |
| Xcode (macOS) | DerivedData, documentation cache, device logs, old DeviceSupport folders (the newest two are kept), unavailable simulators |
| Editors and apps | Cursor snapshots and caches, cache folders of Electron apps (Slack, Discord, Postman, VS Code and others), old Claude Code and Cursor Agent versions, app logs |
| Docker | Unused images, containers, networks and build cache (`docker system prune -a`). Volumes are kept. |
| Linux only | Thumbnail cache |

### `clean --deep`

Everything above, plus:

| Category | Items |
| --- | --- |
| Browser caches | Arc, Chrome, Chromium, Brave, Edge, Firefox. Only the disk cache of downloaded pages and images. |
| Browser AI models | The on-device model Chrome and Arc download (about 2.7 GB). It is downloaded again if a feature needs it. |
| Trash | `~/.Trash` on macOS, `~/.local/share/Trash` on Linux. |
| Project build folders | `node_modules`, `.next`, `.nuxt`, `.svelte-kit`, `.angular`, `.astro`, `.expo`, `.turbo`, `.parcel-cache`, `target`, `.gradle`, `Pods`, `vendor`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`. Restore them with your usual install or build command. |

To clean projects stored somewhere else, pass the folder: `clean --deep ~/code`.

### `clean --review`

Interactive. Nothing is removed unless you answer `y`.

| Item | Action on `y` |
| --- | --- |
| Entries in `~/Downloads` over 100 MB, largest first | Moved to the Trash, so you can restore them |
| Node versions installed with nvm (the version in use is skipped; the nvm default is labelled) | Deleted |
| Intel Homebrew in `/usr/local` on Apple Silicon Macs | Removed with [Homebrew's official uninstaller](https://github.com/Homebrew/install#uninstall-homebrew), which asks for your password |
| iOS device backups, Xcode archives, Hugging Face models, Android emulators | Deleted |

Before asking about Intel Homebrew, `cleanspace` lists any packages that are not also installed in `/opt/homebrew`, so you can see what you would lose.

## Safety

The safety rules are adapted from [Mole](https://github.com/tw93/Mole) and [kondo](https://github.com/tbillington/kondo).

- **Personal data is never removed automatically.** Downloads, backups, archives, AI models and Node versions only appear in `--review`, behind a confirmation.
- **Browser profiles are untouched.** History, saved passwords, cookies, autofill, bookmarks and Arc spaces live in the browser profile folder, which `cleanspace` never opens. You stay signed in everywhere.
- **Running browsers are skipped.** A browser's cache is only cleared while the browser is closed.
- **Build folders need their project file.** A folder is only deleted when the matching project file sits next to it. For example, `node_modules` needs `package.json`, `target` needs `Cargo.toml` or `pom.xml`, and `vendor` needs `composer.json`. A random folder that happens to be called `target` or `vendor` is left alone. Hidden folders are never searched.
- **Tools clean their own caches** where they offer a command (`uv cache clean`, `go clean -modcache`, `brew cleanup`) instead of deleting their files directly.
- **No sudo.** The only step that can ask for a password is the Homebrew uninstaller in `--review`, and only after you agree to it.
- **Preview first.** `--dry-run` works with `--deep` and `--review` too.

## Updating and uninstalling

```bash
cleanspace --update   # download the latest version
cleanspace --remove   # delete the script and the lines the installer added
```

After `--remove`, open a new terminal to drop the `clean` alias from your current session.

## FAQ

**The Trash shows as "give your terminal Full Disk Access".**
macOS protects `~/.Trash`. Open System Settings → Privacy & Security → Full Disk Access and enable your terminal app, or empty the Trash from Finder.

**My free space did not go up after deleting Downloads.**
`--review` moves Downloads to the Trash so you can change your mind. Empty the Trash, or run `clean --deep`, to get the space back.

**A browser cache was skipped.**
That browser was open. Quit it and run `clean --deep` again.

**What is "Intel Homebrew (x86)"?**
On an Apple Silicon Mac, Homebrew lives in `/opt/homebrew`. A second copy in `/usr/local` is usually left over from an Intel Mac or a migration and runs through Rosetta. If every tool you use runs from `/opt/homebrew` (check with `which <tool>`), you can remove it through `clean --review`, or directly:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" -- --path=/usr/local
```

**What about system caches on Linux?**
They need root, so `cleanspace` leaves them to you, for example `sudo apt clean` and `sudo journalctl --vacuum-time=2weeks`.

## Contributing

The whole tool is one file, [`cleanspace`](cleanspace), plus the installer, [`install.sh`](install.sh). To add a cache, add one line to the matching section:

```bash
item "Label"  path [path...]                  # removes the paths
item "Label"  path -- tool clean-command      # runs the tool's own command if it is installed
GUARD="App"   item "Label" path               # skipped while "App" is running
```

To work on it locally, link your checkout so your edits run right away and `--update` uses `git pull`:

```bash
git clone https://github.com/Pantho-Haque/cleanspace.git
ln -sf "$PWD/cleanspace/cleanspace" ~/.local/bin/cleanspace
```

Test changes with `clean --dry-run` before running them for real.
