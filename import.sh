#!/usr/bin/env bash
# Load this omp-config snapshot into an omp home (default: ~/.omp).
#
# Usage: ./import.sh [omp_home]
#   omp_home   target omp home (default: ~/.omp)
#
# Non-destructive: sessions/history are untouched, and every file about to be
# replaced (config.yml, models.yml, plugin lockfiles) is backed up to
# <omp_home>/backup-<ts>/ first. __OMP_HOME__ placeholders are rewritten to
# the local home directory; the LAN_LLM API key is written to agent/.env from
# the LAN_LLM_API_KEY env var or an interactive prompt (never overwritten).
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-$HOME/.omp}"

fail() { echo "error: $*" >&2; exit 1; }

[ -f "$SRC/agent/config.yml" ] || fail "no agent/config.yml here — run from an exported omp-config repo"
# Canonicalize before any guard or destructive operation.
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"
[ "$SRC" != "$TARGET" ] || fail "target must not be the repo itself"
case "$TARGET" in "$SRC"|"$SRC"/*) fail "target must not be inside the repo" ;; esac
[ "$TARGET" != "$HOME" ] || fail "target must be an omp home, not \$HOME itself"
command -v perl >/dev/null 2>&1 || fail "perl is required"

# Home directory that contains the omp home on THIS machine.
NEW_HOME="$(cd "$TARGET/.." && pwd)"

# Back up each file right before it is replaced (lazy, so an untouched
# target creates no backup dir).
BK=""
bkdir() {
  if [ -z "$BK" ]; then
    BK="$TARGET/backup-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$BK"
    chmod 700 "$BK"
    echo "backed up replaced files to $BK"
  fi
}

# ── 1. copy the snapshot in (overlay; never touches sessions) ────────────
mkdir -p "$TARGET/agent"
if [ -f "$TARGET/agent/config.yml" ]; then bkdir; cp "$TARGET/agent/config.yml" "$BK/"; fi
cp "$SRC/agent/config.yml" "$TARGET/agent/"
if [ -f "$TARGET/agent/models.yml" ]; then bkdir; cp "$TARGET/agent/models.yml" "$BK/"; fi
cp "$SRC/agent/models.yml" "$TARGET/agent/"
for d in agents skills commands; do
  # Replace wholesale so deletions on the source machine propagate on re-import.
  if [ -d "$SRC/agent/$d" ]; then
    if [ -d "$TARGET/agent/$d" ]; then bkdir; cp -R "$TARGET/agent/$d" "$BK/"; fi
    rm -rf "$TARGET/agent/$d"
    cp -R "$SRC/agent/$d" "$TARGET/agent/"
  fi
done
if [ -f "$SRC/agent/.env.example" ]; then cp "$SRC/agent/.env.example" "$TARGET/agent/"; fi

if [ -d "$SRC/plugins" ]; then
  for f in omp-plugins.lock.json installed_plugins.json; do
    if [ -f "$TARGET/plugins/$f" ]; then bkdir; cp "$TARGET/plugins/$f" "$BK/"; fi
  done
  rm -rf "$TARGET/plugins"
  cp -R "$SRC/plugins" "$TARGET/plugins"
fi
for f in marketplaces.json migrate-claude-agents.sh; do
  if [ -f "$SRC/$f" ]; then cp "$SRC/$f" "$TARGET/"; fi
done

# ── 2. placeholder -> this machine's home (literal replace, no regex) ────
for f in "$TARGET/marketplaces.json" "$TARGET/plugins/installed_plugins.json"; do
  if [ -f "$f" ]; then
    NEW_HOME="$NEW_HOME" perl -pi -e '$_ = join($ENV{NEW_HOME}, split /\Q__OMP_HOME__\E/)' "$f"
  fi
done

if [ -d "$TARGET/plugins/node_modules" ]; then
  while IFS= read -r link; do
    tgt=$(readlink "$link")
    case "$tgt" in
      __OMP_HOME__/*) rm "$link"; ln -s "$NEW_HOME${tgt#__OMP_HOME__}" "$link" ;;
    esac
  done < <(find "$TARGET/plugins/node_modules" -type l)
fi

# ── 3. API key (.env) — created restrictive from the start ───────────────
ENVF="$TARGET/agent/.env"
if [ ! -f "$ENVF" ]; then
  if [ -n "${LAN_LLM_API_KEY:-}" ]; then
    ( umask 077; printf 'LAN_LLM_API_KEY=%s\n' "$LAN_LLM_API_KEY" > "$ENVF" )
    echo "wrote $ENVF from LAN_LLM_API_KEY environment variable"
  else
    printf 'Enter LAN_LLM API key (hidden; empty to skip): '
    key=""
    IFS= read -rs key || key=""
    echo
    if [ -n "$key" ]; then
      ( umask 077; printf 'LAN_LLM_API_KEY=%s\n' "$key" > "$ENVF" )
      echo "wrote $ENVF"
    else
      echo "warning: skipped — create $ENVF with LAN_LLM_API_KEY=<key> before first run" >&2
    fi
  fi
fi
if [ -f "$ENVF" ]; then chmod 600 "$ENVF"; fi

# ── 4. self-check ────────────────────────────────────────────────────────
status=0
if [ -d "$TARGET/plugins/node_modules" ]; then
  while IFS= read -r link; do
    if [ ! -e "$link" ]; then
      echo "broken symlink: $link -> $(readlink "$link")" >&2
      status=1
    fi
  done < <(find "$TARGET/plugins/node_modules" -type l)
fi
for f in "$TARGET/marketplaces.json" "$TARGET/plugins/installed_plugins.json"; do
  if [ -f "$f" ] && grep -q '__OMP_HOME__' "$f"; then
    echo "unresolved __OMP_HOME__ placeholder in $f" >&2
    status=1
  fi
done

echo
echo "loaded config into $TARGET"
echo "verify:"
echo "  omp config path"
echo "  omp models lan-llm --json"
echo "  omp plugin list"
exit $status
