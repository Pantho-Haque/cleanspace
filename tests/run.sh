#!/usr/bin/env bash
# Tests for cleanspace. Every test runs against a throwaway $HOME with stubbed tools
# (docker, brew, go, xcrun, ...), so nothing on the real machine is touched.
# Usage: tests/run.sh
cd "$(dirname "$0")/.." || exit 1
CS=$PWD/cleanspace
pass=0 fail=0

new_home() {
  H=$(mktemp -d "${TMPDIR:-/tmp}/cs-test.XXXXXX")
  H=$(cd -P "$H" && pwd -P)
  mkdir -p "$H/stub"
  for t in docker brew go uv conda xcrun osascript notify-send launchctl systemctl crontab; do
    printf '#!/bin/sh\nexit 1\n' > "$H/stub/$t"; chmod +x "$H/stub/$t"
  done
  printf '#!/bin/sh\nexit 1\n' > "$H/stub/pgrep"; chmod +x "$H/stub/pgrep"   # no app is "running"
  if [ "$(uname -s)" = Darwin ]; then CACHE=$H/Library/Caches S_DIR="$H/Library/Application Support"
  else CACHE=$H/.cache S_DIR=$H/.config; fi
}
cs() { env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb "$CS" "$@"; }
mk() { mkdir -p "$(dirname "$1")"; head -c "${2:-20000}" /dev/zero > "$1"; }   # mk file [bytes]
old() { find "$@" -exec touch -t 202001010000 {} + ; }                        # make files look untouched for years

check() {  # check "name" condition...
  local name=$1; shift
  if "$@"; then pass=$((pass + 1)); echo "ok   $name"
  else fail=$((fail + 1)); echo "FAIL $name"; [ -n "$OUT" ] && printf '%s\n' "$OUT" | sed 's/^/     | /'; fi
}
exists() { [ -e "$1" ]; }
gone()   { [ ! -e "$1" ]; }
has()    { printf '%s' "$OUT" | grep -q -- "$1"; }

# ---- basics
new_home
OUT=$(cs --version); check "--version" has "cleanspace 2"
OUT=$(cs --help);    check "--help lists options" has "--schedule"
OUT=$(cs --bogus 2>&1); rc=$?; check "unknown option exits 1" [ $rc = 1 ]
OUT=$(cs --older abc 2>&1); rc=$?; check "--older validates" [ $rc = 1 ]

# ---- dry run deletes nothing
mk "$H/.npm/_cacache/blob"
mk "$CACHE/pip/http/x"
OUT=$(cs --dry-run); rc=$?
check "dry run exit 0" [ $rc = 0 ]
check "dry run lists npm" has "npm cache"
check "dry run shows how it comes back" has "re-downloads when needed"
check "dry run keeps files" exists "$H/.npm/_cacache/blob"
check "dry run takes no lock" gone "$H/.local/state/cleanspace/lock"

# ---- no terminal and no --yes: refuse
OUT=$(cs 2>&1 </dev/null); rc=$?
check "non-interactive without --yes exits 2" [ $rc = 2 ]
check "non-interactive without --yes keeps files" exists "$H/.npm/_cacache/blob"

# ---- --yes cleans caches, keeps personal data and exclusions
mk "$H/Downloads/movie.mp4"
mk "$CACHE/composer/repo/x"
mkdir -p "$H/.config/cleanspace"
printf 'exclude = composer cache\nexclude = ~/.cache/pip-nope\n' > "$H/.config/cleanspace/config"
OUT=$(cs --yes); rc=$?
check "--yes exit 0" [ $rc = 0 ]
check "--yes removes npm cache" gone "$H/.npm/_cacache"
check "--yes removes pip cache" gone "$CACHE/pip"
check "Downloads untouched" exists "$H/Downloads/movie.mp4"
check "excluded label kept" exists "$CACHE/composer/repo/x"
check "lock released" gone "$H/.local/state/cleanspace/lock"
check "history recorded" grep -q "npm cache" "$H/.local/state/cleanspace/history.tsv"
check "history rows are tab-separated" eval "awk -F'\t' 'NF == 4 && \$2 == \"npm cache\"' '$H/.local/state/cleanspace/history.tsv' | grep -q ."
printf '1700000000    pip / Pipenv cache    2048    2048\n' >> "$H/.local/state/cleanspace/history.tsv"   # a row from before 2.2
OUT=$(cs --stats); check "--stats shows total" has "Freed"
check "--stats lists what was freed" has "npm cache"
check "--stats reads rows written before 2.2" has "pip / Pipenv cache"
check "--stats shows the first date" has "since 20"

# ---- symlinks pointing outside are not followed
mkdir -p "$H/outside" "$H/.npm"; mk "$H/outside/precious"
ln -s "$H/outside" "$H/.npm/_cacache"
OUT=$(cs --yes)
check "symlink target survives" exists "$H/outside/precious"

# ---- interactive selection: skip item 1
new_home
mk "$H/.npm/_cacache/blob"; mk "$CACHE/pip/http/x"
echo "1" > "$H/answers"
OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb CLEANSPACE_INPUT="$H/answers" "$CS")
check "skipped item 1 (npm) kept" exists "$H/.npm/_cacache/blob"
check "item 2 (pip) cleaned" gone "$CACHE/pip"
echo "n" > "$H/answers"; mk "$CACHE/pip/http/x"
OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb CLEANSPACE_INPUT="$H/answers" "$CS")
check "answer n cancels" exists "$CACHE/pip/http/x"

# ---- running app guard
new_home
mk "$CACHE/Firefox/x"; mk "$CACHE/mozilla/x"
printf '#!/bin/sh\nexit 0\n' > "$H/stub/pgrep"            # every app "running"
mkdir -p "$H/code"; OUT=$(cs --deep "$H/code" --yes)
check "browser cache skipped while browser runs" has "is running"
check "browser cache kept while browser runs" exists "$CACHE/Firefox/x"

# ---- concurrent runs are refused
new_home
mkdir -p "$H/.local/state/cleanspace/lock"; echo $$ > "$H/.local/state/cleanspace/lock/pid"
OUT=$(cs --yes 2>&1); rc=$?
check "second run refused while locked" [ $rc = 1 ]
echo 999999 > "$H/.local/state/cleanspace/lock/pid"
OUT=$(cs --yes 2>&1); rc=$?
check "stale lock is taken over" [ $rc = 0 ]

# ---- --deep project builds
new_home
P=$H/code
mk "$P/old/package.json" 10;      mk "$P/old/node_modules/a/index.js"
mk "$P/fresh/package.json" 10;    mk "$P/fresh/node_modules/a/index.js"
mk "$P/orphan/node_modules/a/x"                                  # no package.json next to it
mk "$P/rand/target/x"                                            # no Cargo.toml / pom.xml
mk "$P/php/composer.json" 10;     mk "$P/php/vendor/lib/x"       # vendor committed to git
mk "$P/py/app.py" 10;             mk "$P/py/__pycache__/app.pyc"
mk "$P/.hidden/package.json" 10;  mk "$P/.hidden/node_modules/x"
(cd "$P/php" && git init -q && git add -f vendor composer.json && git -c user.email=t@t -c user.name=t commit -qm init)
mk "$P/net/app.csproj" 10;        mk "$P/net/bin/Debug/app.dll"  # .NET output
mk "$P/gr/build.gradle" 10;       mk "$P/gr/build/libs/x.jar"    # Gradle output
mk "$P/docs/build/index.html"                                    # a plain "build" folder, no project file
mk "$P/unity/Assembly-CSharp.csproj" 10; mk "$P/unity/Library/x"  # Unity cache
mk "$P/notunity/Library/book.pdf"                                # a folder that just happens to be called Library
mk "$P/pyproj/pyproject.toml" 10;   mk "$P/pyproj/.venv/pyvenv.cfg" 10; mk "$P/pyproj/.venv/lib/x"
mk "$P/reqs/requirements.txt" 10; mk "$P/reqs/venv/pyvenv.cfg" 10;  mk "$P/reqs/venv/lib/x"
mk "$P/novenv/pyproject.toml" 10; mk "$P/novenv/.venv/notes.txt"             # called .venv but not a virtualenv
mk "$P/loose/.venv/pyvenv.cfg" 10                                            # a virtualenv with no project file
old "$P/old" "$P/php" "$P/py" "$P/orphan" "$P/rand" "$P/net" "$P/gr" "$P/docs" "$P/unity" "$P/notunity" \
    "$P/pyproj" "$P/reqs" "$P/novenv" "$P/loose"
touch "$P/fresh/package.json"
OUT=$(cs --deep "$P" --yes)
check "stale node_modules removed"        gone   "$P/old/node_modules"
check "recently edited project kept"      exists "$P/fresh/node_modules"
check "node_modules without package.json" exists "$P/orphan/node_modules"
check "random target folder kept"         exists "$P/rand/target"
check "git-tracked vendor kept"           exists "$P/php/vendor/lib/x"
check "__pycache__ removed"               gone   "$P/py/__pycache__"
check "hidden folders not searched"       exists "$P/.hidden/node_modules"
check ".NET bin removed"                  gone   "$P/net/bin"
check "Gradle build removed"              gone   "$P/gr/build"
check "plain build folder kept"           exists "$P/docs/build/index.html"
check "Unity Library removed"             gone   "$P/unity/Library"
check "non-Unity Library kept"            exists "$P/notunity/Library/book.pdf"
check ".venv removed"                     gone   "$P/pyproj/.venv"
check "venv removed"                      gone   "$P/reqs/venv"
check ".venv that is not a virtualenv kept" exists "$P/novenv/.venv/notes.txt"
check "virtualenv without a project kept" exists "$P/loose/.venv/pyvenv.cfg"
check "kept projects are reported"        has    "edited in the last 14 days"
OUT=$(cs --deep "$P" --older 0 --yes)
check "--older 0 includes recent projects" gone "$P/fresh/node_modules"

# ---- rules learned from Mole's source
new_home
mk "$H/.npm/_npx/abc/node_modules/x/index.js"
printf '#!/bin/sh\n[ "$1" = -f ] && exit 0\nexit 1\n' > "$H/stub/pgrep"      # something runs from _npx
mk "$CACHE/deno/location_data/x/local_storage"; mk "$CACHE/deno/deps/https/x"
mk "$S_DIR/NotElectron/Cache/data.db"                                         # a "Cache" with no Chromium marker
mk "$S_DIR/Slack/Code Cache/js/x"; mk "$S_DIR/Slack/Cache/x"                  # a real Electron app
mk "$H/.vscode/extensions/pub.ext-1.0.0/package.json"; mk "$H/.vscode/extensions/pub.ext-2.0.0/package.json"
printf '{"pub.ext-1.0.0":true}' > "$H/.vscode/extensions/.obsolete"
OUT=$(cs --yes)
check "npx cache kept while in use"       exists "$H/.npm/_npx/abc/node_modules/x/index.js"
check "Deno localStorage kept"            exists "$CACHE/deno/location_data/x/local_storage"
check "Deno deps removed"                 gone   "$CACHE/deno/deps"
check "Cache without Chromium marker kept" exists "$S_DIR/NotElectron/Cache/data.db"
check "Electron app Cache removed"        gone   "$S_DIR/Slack/Cache"
check "obsolete extension removed"        gone   "$H/.vscode/extensions/pub.ext-1.0.0"
check "current extension kept"            exists "$H/.vscode/extensions/pub.ext-2.0.0"

new_home
P=$H/code
mk "$P/sol/Cargo.toml" 10; mk "$P/sol/target/deploy/prog-keypair.json"; mk "$P/sol/target/debug/x"
mk "$P/gitdep/package.json" 10; mk "$P/gitdep/node_modules/dep/.git/HEAD"
old "$P"
OUT=$(cs --deep "$P" --yes)
check "target with a keypair kept"        exists "$P/sol/target/deploy/prog-keypair.json"
check "node_modules holding a repo kept"  exists "$P/gitdep/node_modules/dep/.git/HEAD"

new_home
mk "$CACHE/ms-playwright/chromium/x"; mk "$H/.npm/_cacache/x"
mkdir -p "$H/.config/cleanspace"; echo "auto_below_gb = 999999" > "$H/.config/cleanspace/config"
OUT=$(cs --auto)
check "--auto cleans when space is low"   gone   "$H/.npm/_cacache"
check "--auto leaves Playwright browsers" exists "$CACHE/ms-playwright/chromium/x"

# ---- Docker: the stub expands the --format template the way docker does, \t included
new_home
cat > "$H/stub/docker" <<'EOF'
#!/bin/sh
case $1 in
  info) exit 0 ;;
  system) for row in 'Images|8GB (74%)' 'Build Cache|2GB' 'Local Volumes|5GB (0%)'; do
            printf '%s\n' "$4" | awk -v t="${row%%|*}" -v r="${row#*|}" \
              '{ gsub(/\\t/, "\t"); gsub(/\{\{\.Type\}\}/, t); gsub(/\{\{\.Reclaimable\}\}/, r); print }'
          done ;;
  *) touch "$HOME/docker-pruned" ;;
esac
EOF
OUT=$(cs --dry-run)
check "Docker reclaimable space is measured" has "Docker images & build cache *9.3G"
OUT=$(cs --yes)
check "Docker is pruned" exists "$H/docker-pruned"

# ---- Docker build cache cap
new_home
mk "$H/.npm/_cacache/x"; mkdir -p "$H/.docker"
printf '{\n  "builder": {\n    "gc": {\n      "defaultKeepStorage": "20GB",\n      "enabled": true\n    }\n  }\n}\n' > "$H/.docker/daemon.json"
echo n > "$H/answers"
OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb CLEANSPACE_INPUT="$H/answers" "$CS" --dry-run)
check "Docker cap is offered" has "Cap it at 5GB"
check "dry run leaves daemon.json" grep -q '"20GB"' "$H/.docker/daemon.json"
echo y > "$H/answers"
OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb CLEANSPACE_INPUT="$H/answers" "$CS")
check "Docker cap written" grep -q '"defaultKeepStorage": "5GB"' "$H/.docker/daemon.json"
check "daemon.json keeps its other settings" grep -q '"enabled": true' "$H/.docker/daemon.json"
mk "$H/.npm/_cacache/x"
OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb CLEANSPACE_INPUT="$H/answers" "$CS")
check "Docker cap not offered once capped" eval "! printf '%s' \"\$OUT\" | grep -q 'Cap it'"

if [ "$(uname -s)" = Darwin ]; then
  # ---- schedule: a script kept on the Desktop runs from a copy launchd may read
  new_home
  printf '#!/bin/sh\nexit 0\n' > "$H/stub/launchctl"
  mkdir -p "$H/Desktop/cleanspace" "$H/.local/bin"; cp "$CS" "$H/Desktop/cleanspace/cleanspace"
  ln -s "$H/Desktop/cleanspace/cleanspace" "$H/.local/bin/cleanspace"
  csl() { env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb "$H/.local/bin/cleanspace" "$@"; }
  PL=$H/Library/LaunchAgents/io.github.pantho-haque.cleanspace.plist COPY=$H/.local/state/cleanspace/cleanspace
  OUT=$(csl --schedule)
  check "schedule copies a Desktop script" exists "$COPY"
  check "schedule runs the copy" grep -q "<string>$COPY</string>" "$PL"
  echo '# edited' >> "$H/Desktop/cleanspace/cleanspace"; OUT=$(csl --dry-run)
  check "a manual run refreshes the copy" cmp -s "$COPY" "$H/Desktop/cleanspace/cleanspace"
  OUT=$(csl --schedule off)
  check "schedule off removes the copy" gone "$COPY"
  rm "$H/.local/bin/cleanspace"; cp "$CS" "$H/.local/bin/cleanspace"; OUT=$(csl --schedule)
  check "schedule runs a normal install directly" grep -q "<string>$H/.local/bin/cleanspace</string>" "$PL"

  # ---- quit a running app to clean its cache, then reopen it
  new_home
  mk "$CACHE/Firefox/x" 200000000; mk "$H/.npm/_cacache/x"; mkdir -p "$H/Applications/firefox.app" "$H/code"; touch "$H/running"
  printf '#!/bin/sh\n[ -f "$HOME/running" ]\n' > "$H/stub/pgrep"
  printf '#!/bin/sh\nrm -f "$HOME/running"\n' > "$H/stub/osascript"
  printf '#!/bin/sh\ntouch "$HOME/reopened"\n' > "$H/stub/open"; chmod +x "$H/stub/"*
  echo y > "$H/answers"
  OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb CLEANSPACE_INPUT="$H/answers" "$CS" --deep "$H/code")
  check "offers to quit the running app" has "Quit firefox to clean it"
  check "cache of the quit app removed" gone "$CACHE/Firefox"
  check "quit app is reopened" exists "$H/reopened"
  touch "$H/running"; mk "$CACHE/Firefox/x" 200000000; rm -f "$H/reopened"
  OUT=$(cs --deep "$H/code" --yes)
  check "--yes never quits apps" exists "$CACHE/Firefox/x"
fi

# ---- a cache dir that points at home is not trusted
new_home
mk "$H/Documents/thesis.docx"; old "$H/Documents"
OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb XDG_CACHE_HOME="$H" "$CS" --deep "$H/Documents" --yes 2>&1)
check "XDG_CACHE_HOME=home keeps documents" exists "$H/Documents/thesis.docx"

# ---- config file
new_home
OUT=$(cs --config); check "--config creates file" exists "$H/.config/cleanspace/config"
printf 'bogus line\n' >> "$H/.config/cleanspace/config"
OUT=$(cs --dry-run 2>&1); check "bad config line warns" has "ignoring"

# ---- remove
new_home
cp "$CS" "$H/cs"; mkdir -p "$H/.local/state/cleanspace" "$H/.config/cleanspace"
printf 'alias clean="cleanspace" # cleanspace\nkeep me\n' > "$H/.zshrc"
OUT=$(env -i HOME="$H" PATH="$H/stub:/usr/bin:/bin" TERM=dumb "$H/cs" --remove)
check "--remove deletes script"  gone "$H/cs"
check "--remove deletes state"   gone "$H/.local/state/cleanspace"
check "--remove keeps other rc lines" grep -q "keep me" "$H/.zshrc"
check "--remove drops rc lines" eval "! grep -q cleanspace '$H/.zshrc'"

rm -rf "${TMPDIR:-/tmp}"/cs-test.*
echo; echo "$pass passed, $fail failed"
[ $fail = 0 ]
