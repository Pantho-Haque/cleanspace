#!/usr/bin/env bash
# Install cleanspace:  curl -fsSL https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main/install.sh | bash
set -e
RAW=https://raw.githubusercontent.com/Pantho-Haque/cleanspace/main
DIR="$HOME/.local/bin"
OS=$(uname -s)

case "$OS" in Darwin|Linux) ;; *) echo "cleanspace supports macOS and Linux only (got $OS)"; exit 1 ;; esac
command -v curl >/dev/null || { echo "curl is required"; exit 1; }

mkdir -p "$DIR"
curl -fsSL "$RAW/cleanspace" -o "$DIR/cleanspace.tmp"
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

echo "✓ cleanspace installed to $DIR/cleanspace ($OS)"
echo "  Run: source $RC   (or open a new terminal), then: clean"
