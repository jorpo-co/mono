#!/bin/sh
# mono — install script
# Usage:
#   curl -sSL https://raw.githubusercontent.com/jorpo-co/mono/main/install.sh | bash
#   curl -sSL https://raw.githubusercontent.com/jorpo-co/mono/v1.2.3/install.sh | bash
#   bash install.sh                    # from local clone
#   bash install.sh --help
#
# Non-interactive (set env vars):
#   SKILL_DIR=~/.agents/skills/mono BIN_DIR=~/.local/bin bash install.sh

set -e

REPO="jorpo-co/mono"
BRANCH="${BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
VERSION="0.1.0"

# --- helpers ---

red()     { printf '\033[31m%s\033[0m\n' "$*"; }
green()   { printf '\033[32m%s\033[0m\n' "$*"; }
bold()    { printf '\033[1m%s\033[0m\n' "$*"; }
dim()     { printf '\033[2m%s\033[0m\n' "$*"; }

die()     { red "error: $*"; exit 1; }
usage()   {
  cat <<EOF
Usage: install.sh [OPTIONS]

Install mono binary + AI agent skill.

Options:
  --bin-dir DIR     Binary install directory (default: /usr/local/bin)
  --skill-dir DIR   Skill install directory (prompted if omitted)
  --local           Use local files instead of downloading from GitHub
  --branch NAME     GitHub branch or tag to download from (default: main)
  --version         Print version and exit
  --help            Show this message

Non-interactive mode: set SKILL_DIR and/or BIN_DIR env vars, or pass --bin-dir --skill-dir.

Examples:
  curl -sSL https://raw.githubusercontent.com/jorpo-co/mono/main/install.sh | bash
  bash install.sh --bin-dir ~/.local/bin --skill-dir ~/.agents/skills/mono
  SKILL_DIR=~/.agents/skills/mono BIN_DIR=~/.local/bin bash install.sh
EOF
  exit 0
}

prompt() {
  printf "%s " "$1" >&2
  read -r val
  printf "%s" "$val"
}

confirm() {
  printf "%s [y/N] " "$1"
  read -r resp
  case "$resp" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# --- flags ---

local_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage ;;
    --version) echo "mono-install $VERSION"; exit 0 ;;
    --local) local_mode=true; shift ;;
    --branch) BRANCH="$2"; RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"; shift 2 ;;
    --bin-dir) BIN_DIR="$2"; shift 2 ;;
    --skill-dir) SKILL_DIR="$2"; shift 2 ;;
    *) die "unknown flag: $1. Use --help for usage." ;;
  esac
done

# --- source: local or remote ---

if [ "$local_mode" = true ]; then
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  [ -f "$script_dir/mono" ] || die "local mode: mono binary not found in $script_dir"
  [ -f "$script_dir/skills/mono/SKILL.md" ] || die "local mode: skills/mono/SKILL.md not found in $script_dir"
  copy_file() { cp "$1" "$2"; }
  src_bin="$script_dir/mono"
  src_skill="$script_dir/skills/mono"
  echo "Using local files from $script_dir"
else
  download() {
    curl -sfL "$1" -o "$2" || die "failed to download $1"
  }
  echo "Downloading from $RAW_BASE"
fi
echo ""

# --- preamble ---

bold "mono — Git submodule monorepo manager"
dim "Source: https://github.com/$REPO"
echo ""

# --- detect existing binary (interactive only) ---

interactive=false
[ -t 0 ] && interactive=true

if [ -z "${BIN_DIR:-}" ] && [ "$interactive" = true ]; then
  if command -v mono >/dev/null 2>&1; then
    existing=$(command -v mono)
    if confirm "mono binary found at $existing. Overwrite?"; then
      :  # proceed
    else
      echo "Skipping binary install."
      skip_binary=true
    fi
  fi
fi

# --- determine skill directory ---

if [ -n "${SKILL_DIR:-}" ]; then
  skill_dir="$SKILL_DIR"
elif [ "$interactive" = false ]; then
  die "SKILL_DIR not set and no interactive terminal. Pass --skill-dir or set SKILL_DIR env var."
else
  echo ""
  bold "Step 1: Where should the skill live?"
  echo ""
  cat <<MENU
  1) Project-level  — inside this project directory
                      (.agents/skills/  .github/skills/  .claude/skills/)
  2) User-level      — in your home directory
                      (~/.agents/skills/  ~/.copilot/skills/  ~/.claude/skills/)
  3) Custom path     — specify any directory
MENU

  skill_scope=$(prompt "Choose [1-3]:")
  case "$skill_scope" in
    1)
      echo ""; bold "Which agent?"; echo ""
      cat <<AGENTS
  1) Any agent (cross-agent standard)   → .agents/skills/mono/
  2) GitHub Copilot                     → .github/skills/mono/
  3) Claude Code                         → .claude/skills/mono/
  4) Custom project subdirectory
AGENTS
      agent=$(prompt "Choose [1-4]:")
      case "$agent" in
        1) skill_dir=".agents/skills/mono" ;;
        2) skill_dir=".github/skills/mono" ;;
        3) skill_dir=".claude/skills/mono" ;;
        4) skill_dir="$(prompt "Relative path (e.g. .config/my-agent/skills/mono):")" ;;
        *) die "invalid choice" ;;
      esac
      skill_dir="$(pwd)/$skill_dir"
      ;;
    2)
      echo ""; bold "Which agent?"; echo ""
      cat <<AGENTS
  1) Any agent (cross-agent standard)   → ~/.agents/skills/mono/
  2) GitHub Copilot                     → ~/.copilot/skills/mono/
  3) Claude Code                         → ~/.claude/skills/mono/
  4) Custom user directory
AGENTS
      agent=$(prompt "Choose [1-4]:")
      case "$agent" in
        1) skill_dir="$HOME/.agents/skills/mono" ;;
        2) skill_dir="$HOME/.copilot/skills/mono" ;;
        3) skill_dir="$HOME/.claude/skills/mono" ;;
        4) skill_dir="$(prompt "Full path (e.g. /home/user/.my-agent/skills/mono):")" ;;
        *) die "invalid choice" ;;
      esac
      ;;
    3)
      skill_dir="$(prompt "Full path to skill directory (e.g. /home/user/.my-agent/skills/mono):")"
      ;;
    *) die "invalid choice" ;;
  esac
fi

# --- determine binary directory ---

if [ -z "${BIN_DIR:-}" ]; then
  if [ "${skip_binary:-false}" != true ]; then
    if [ "$interactive" = true ]; then
      echo ""; bold "Step 2: Binary install location"; echo ""
      default_bin="/usr/local/bin"
      bin_dir=$(prompt "Binary directory [${default_bin}]:")
      bin_dir="${bin_dir:-$default_bin}"
    else
      bin_dir="/usr/local/bin"
    fi
  fi
else
  bin_dir="$BIN_DIR"
fi

# --- confirm ---

if [ "$interactive" = true ]; then
  echo ""; bold "Ready to install:"; echo ""
  if [ "${skip_binary:-false}" != true ]; then
    echo "  binary  → $bin_dir/mono"
  fi
  echo "  skill   → $skill_dir/"
  echo ""
  if ! confirm "Proceed?"; then
    echo "Aborted."; exit 0
  fi
fi

# --- install ---

echo ""; bold "Installing..."; echo ""

if [ "$local_mode" = true ]; then
  if [ "${skip_binary:-false}" != true ]; then
    mkdir -p "$bin_dir"
    cp "$src_bin" "$bin_dir/mono" && chmod 755 "$bin_dir/mono"
    green "  ✓  binary  → $bin_dir/mono"
  fi
  mkdir -p "$skill_dir/references"
  cp "$src_skill/SKILL.md" "$skill_dir/SKILL.md"
  cp "$src_skill/references/COMMANDS.md" "$skill_dir/references/COMMANDS.md"
  green "  ✓  skill   → $skill_dir/"
else
  tmpdir="$(mktemp -d /tmp/mono-install.XXXXXX)"
  trap 'rm -rf "$tmpdir"' EXIT

  if [ "${skip_binary:-false}" != true ]; then
    download "$RAW_BASE/mono" "$tmpdir/mono"
    mkdir -p "$bin_dir"
    install -m 755 "$tmpdir/mono" "$bin_dir/mono"
    green "  ✓  binary  → $bin_dir/mono"
  fi

  mkdir -p "$skill_dir/references"
  download "$RAW_BASE/skills/mono/SKILL.md" "$skill_dir/SKILL.md"
  download "$RAW_BASE/skills/mono/references/COMMANDS.md" "$skill_dir/references/COMMANDS.md"
  green "  ✓  skill   → $skill_dir/SKILL.md"
  green "  ✓  skill   → $skill_dir/references/COMMANDS.md"
fi

# --- done ---

echo ""; bold "Done."; echo ""

if [ "${skip_binary:-false}" != true ]; then
  echo "  mono binary installed. Ensure $bin_dir is in your PATH."
fi
echo "  Skill ready. Agents supporting Agent Skills"
echo "  will auto-discover mono from $skill_dir."
echo ""
dim "  Quick start:  mono init && mono module add my-module"
echo ""