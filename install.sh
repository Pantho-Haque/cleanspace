#!/usr/bin/env bash
# Install cleanspace:  curl -fsSL https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main/install.sh | bash
set -e
RAW=https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main
DIR="$HOME/.local/bin"
OS=$(uname -s)

case "$OS" in Darwin|Linux) ;; *) echo "cleanspace supports macOS and Linux only (got $OS)"; exit 1 ;; esac
command -v curl >/dev/null || { echo "curl is required"; exit 1; }
command -v bash >/dev/null || { echo "bash is required"; exit 1; }

mkdir -p "$DIR"
curl -fsSL --retry 3 "$RAW/cleanspace" -o "$DIR/cleanspace.tmp"
if ! bash -n "$DIR/cleanspace.tmp" 2>/dev/null || ! grep -q '^VERSION=' "$DIR/cleanspace.tmp"; then
  rm -f "$DIR/cleanspace.tmp"; echo "download looks broken, nothing installed"; exit 1
fi
chmod +x "$DIR/cleanspace.tmp"
mv -f "$DIR/cleanspace.tmp" "$DIR/cleanspace"

case "$(basename "${SHELL:-bash}")" in
  zsh) RC=~/.zshrc ;;
  *)   [ "$OS" = Darwin ] && RC=~/.bash_profile || RC=~/.bashrc ;;
esac
touch "$RC"
add() { grep -qF "$1" "$RC" || echo "$1 # cleanspace" >> "$RC"; }
case ":$PATH:" in *":$DIR:"*) ;; *) add 'export PATH="$HOME/.local/bin:$PATH"' ;; esac
add 'alias clean="cleanspace"'

echo "✓ $("$DIR/cleanspace" --version) installed to $DIR/cleanspace ($OS)"
echo "  Run: source $RC   (or open a new terminal), then:"
echo "    clean --dry-run       see what can be freed"
echo "    clean                 clean (shows the plan and asks first)"
echo "    clean --schedule      clean automatically when disk space runs low"
