#!/usr/bin/env bash
# Load this omp-config snapshot into an omp home (default: ~/.omp).
#
# Usage: ./import.sh [omp_home]
#   omp_home   target omp home (default: ~/.omp)
#
# Non-destructive: sessions/history are untouched, and every file about to be
# replaced (config.yml, models.yml, mcp.json, plugin lockfiles) is backed up
# to <omp_home>/backup-<ts>/ first. __OMP_HOME__ placeholders are rewritten to
# the local home directory; plugin npm deps are reinstalled from bun.lock
# (needs network). LAN_LLM_API_KEY and LANGFUSE_API_KEY are written to
# agent/.env from same-named env vars or an interactive prompt (existing
# entries are never overwritten).
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
command -v omp >/dev/null 2>&1 || fail "omp is required (also used as bun to install plugin deps)"

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
if [ -f "$SRC/agent/mcp.json" ]; then
  if [ -f "$TARGET/agent/mcp.json" ]; then bkdir; cp "$TARGET/agent/mcp.json" "$BK/"; fi
  cp "$SRC/agent/mcp.json" "$TARGET/agent/"
fi
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

# npm plugin deps (not in the repo): reinstall pinned versions for this
# platform. omp is a Bun binary, so it can act as bun.
if [ -f "$TARGET/plugins/package.json" ]; then
  ( cd "$TARGET/plugins" && BUN_BE_BUN=1 omp install --frozen-lockfile ) \
    || fail "plugin dependency install failed (network?) — re-run import.sh"
fi

# ── 3. API keys (.env) — created restrictive from the start ──────────────
ENVF="$TARGET/agent/.env"
# ensure_key NAME LABEL: append NAME=<value> unless .env already has it.
ensure_key() {
  name=$1 label=$2
  if [ -f "$ENVF" ] && grep -q "^$name=" "$ENVF"; then return 0; fi
  val="${!name:-}"
  from=""
  if [ -n "$val" ]; then
    from=" from $name environment variable"
  else
    printf 'Enter %s (hidden; empty to skip): ' "$label"
    IFS= read -rs val || val=""
    echo
  fi
  if [ -z "$val" ]; then
    echo "warning: skipped — add $name=<value> to $ENVF before first run" >&2
    return 0
  fi
  # Keep the previous entry's line intact if the file lacks a final newline.
  if [ -s "$ENVF" ] && [ -n "$(tail -c1 "$ENVF")" ]; then echo >> "$ENVF"; fi
  ( umask 077; printf '%s=%s\n' "$name" "$val" >> "$ENVF" )
  echo "wrote $name to $ENVF$from"
}
ensure_key LAN_LLM_API_KEY "LAN_LLM API key"
if [ -f "$TARGET/agent/mcp.json" ] && grep -qF 'LANGFUSE_API_KEY' "$TARGET/agent/mcp.json"; then
  ensure_key LANGFUSE_API_KEY "Langfuse key — base64 of public:secret"
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
echo "  omp plugin list              # includes pi-mcp-adapter"
exit $status
