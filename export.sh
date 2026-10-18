#!/usr/bin/env bash
# Export live omp config into this repo as a portable, secret-free snapshot.
#
# Usage: ./export.sh [--commit] [omp_home]
#   omp_home   source omp home (default: ~/.omp)
#   --commit   stage and commit the result
#
# The snapshot never contains: sessions, history, model caches, agent.db,
# .env, or the literal API key (models.yml stores an env-var name instead).
# Absolute home paths in plugin metadata are stored as __OMP_HOME__ and
# rewritten back by import.sh, so the repo is username-agnostic.
set -eu

COMMIT=0
SRC="$HOME/.omp"
for arg in "$@"; do
  case "$arg" in
    --commit) COMMIT=1 ;;
    *) SRC="$arg" ;;
  esac
done

DEST="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "error: $*" >&2; exit 1; }

[ -f "$SRC/agent/config.yml" ] || fail "$SRC/agent/config.yml not found (is $SRC an omp home?)"
[ "$SRC" != "$DEST" ] || fail "source must not be the repo itself"
command -v perl >/dev/null 2>&1 || fail "perl is required"

# Home that contains the omp home; placeholder base for portable paths.
OLD_HOME="$(cd "$SRC/.." && pwd)"

# ── 1. stage the whitelisted subset ──────────────────────────────────────
rm -rf "$DEST/agent" "$DEST/plugins"
rm -f "$DEST/marketplaces.json" "$DEST/migrate-claude-agents.sh"
mkdir -p "$DEST/agent"

cp "$SRC/agent/config.yml" "$SRC/agent/models.yml" "$DEST/agent/"
for d in agents skills commands; do
  if [ -d "$SRC/agent/$d" ]; then cp -R "$SRC/agent/$d" "$DEST/agent/"; fi
done

if [ -d "$SRC/plugins" ]; then
  cp -R "$SRC/plugins" "$DEST/plugins"
  # Nested .git dirs (marketplace catalog clones) cannot be tracked.
  find "$DEST/plugins" -type d -name .git -prune -exec rm -rf {} +
fi
for f in marketplaces.json migrate-claude-agents.sh; do
  if [ -f "$SRC/$f" ]; then cp "$SRC/$f" "$DEST/"; fi
done

# ── 2. make the snapshot machine-independent ─────────────────────────────
# models.yml: literal key -> env-var name (omp resolves env names natively).
perl -pi -e 's{^(\s*apiKey:)\s*\S.*$}{$1 LAN_LLM_API_KEY}' "$DEST/agent/models.yml"

cat > "$DEST/agent/.env.example" <<'EOF'
# Copy to agent/.env (gitignored) on this machine, or let import.sh prompt
# for the value. omp also reads LAN_LLM_API_KEY from the process environment.
LAN_LLM_API_KEY=
EOF

# Absolute old-home paths -> __OMP_HOME__ placeholder.
for f in "$DEST/marketplaces.json" "$DEST/plugins/installed_plugins.json"; do
  if [ -f "$f" ]; then OLD_HOME="$OLD_HOME" perl -pi -e 's{\Q$ENV{OLD_HOME}\E}{__OMP_HOME__}g' "$f"; fi
done

if [ -d "$DEST/plugins/node_modules" ]; then
  while IFS= read -r link; do
    tgt=$(readlink "$link")
    case "$tgt" in
      "$OLD_HOME"/*) rm "$link"; ln -s "__OMP_HOME__${tgt#"$OLD_HOME"}" "$link" ;;
    esac
  done < <(find "$DEST/plugins/node_modules" -type l)
fi

# ── 3. secret gate ───────────────────────────────────────────────────────
leaked=$(grep -RIlE 'sk-[A-Za-z0-9_-]{12,}' "$DEST/agent" "$DEST/marketplaces.json" 2>/dev/null || true)
if [ -n "$leaked" ]; then
  echo "POSSIBLE SECRET STAGED — aborting (fix the files or export rules):" >&2
  grep -RInE 'sk-[A-Za-z0-9_-]{12,}' "$DEST/agent" "$DEST/marketplaces.json" >&2 || true
  exit 1
fi
soft=$(grep -RIlE 'sk-[A-Za-z0-9_-]{12,}' "$DEST/plugins" 2>/dev/null || true)
if [ -n "$soft" ]; then
  echo "note: sk-like strings inside third-party plugin content — review before publishing:" >&2
  echo "$soft" >&2
fi

# ── 4. done ──────────────────────────────────────────────────────────────
echo "staged snapshot from $SRC:"
du -sh "$DEST/agent" "$DEST/plugins" 2>/dev/null | sed 's/^/  /'

if [ "$COMMIT" = 1 ]; then
  git -C "$DEST" add -A
  if ! git -C "$DEST" diff --cached --quiet; then
    git -C "$DEST" commit -m "sync omp config $(date +%Y-%m-%d)"
    echo "committed."
  else
    echo "nothing to commit."
  fi
else
  echo "review and commit when ready:"
  echo "  git -C $DEST add -A && git -C $DEST commit -m 'sync omp config'"
fi
