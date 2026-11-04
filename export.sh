#!/usr/bin/env bash
# Export live omp config into this repo as a portable, secret-free snapshot.
#
# Usage: ./export.sh [--commit] [omp_home]
#   omp_home   source omp home (default: ~/.omp)
#   --commit   stage and commit the result
#
# The snapshot never contains: sessions, history, model caches, agent.db,
# .env, literal API keys (models.yml / mcp.json store env-var names instead),
# or npm-installed plugin deps (import.sh reinstalls them from bun.lock, so
# platform-specific native binaries never enter the repo).
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

# Canonicalize before any guard or destructive operation.
[ -d "$SRC" ] || fail "$SRC is not a directory"
SRC="$(cd "$SRC" && pwd)"
[ -f "$SRC/agent/config.yml" ] || fail "$SRC/agent/config.yml not found (is $SRC an omp home?)"
[ "$SRC" != "$DEST" ] || fail "source must not be the repo itself"
command -v perl >/dev/null 2>&1 || fail "perl is required"

# Home that contains the omp home; placeholder base for portable paths.
OLD_HOME="$(cd "$SRC/.." && pwd)"

# A repo-local agent/.env (gitignored) must survive the staging wipe.
PRESERVED_ENV=""
restore_env() {
  if [ -n "$PRESERVED_ENV" ] && [ -f "$PRESERVED_ENV" ]; then
    mv "$PRESERVED_ENV" "$DEST/agent/.env"
    chmod 600 "$DEST/agent/.env"
  fi
}
if [ -f "$DEST/agent/.env" ]; then
  PRESERVED_ENV="$DEST/.env.preserved"
  mv "$DEST/agent/.env" "$PRESERVED_ENV"
  echo "note: preserved repo agent/.env during staging" >&2
fi
abort() {
  restore_env
  rm -rf "$DEST/agent" "$DEST/plugins"
  exit 1
}

# ── 1. stage the whitelisted subset ──────────────────────────────────────
rm -rf "$DEST/agent" "$DEST/plugins"
rm -f "$DEST/marketplaces.json" "$DEST/migrate-claude-agents.sh"
mkdir -p "$DEST/agent"

cp "$SRC/agent/config.yml" "$SRC/agent/models.yml" "$DEST/agent/"
if [ -f "$SRC/agent/mcp.json" ]; then cp "$SRC/agent/mcp.json" "$DEST/agent/"; fi
for d in agents skills commands; do
  if [ -d "$SRC/agent/$d" ]; then cp -R "$SRC/agent/$d" "$DEST/agent/"; fi
done

if [ -d "$SRC/plugins" ]; then
  cp -R "$SRC/plugins" "$DEST/plugins"
  # Nested .git dirs (marketplace catalog clones) cannot be tracked.
  find "$DEST/plugins" -type d -name .git -prune -exec rm -rf {} +
  # npm deps are reinstalled from bun.lock on import; keep only the
  # marketplace-plugin symlinks omp creates.
  if [ -d "$DEST/plugins/node_modules" ]; then
    find "$DEST/plugins/node_modules" -mindepth 1 -maxdepth 1 ! -type l -exec rm -rf {} +
  fi
fi
for f in marketplaces.json migrate-claude-agents.sh; do
  if [ -f "$SRC/$f" ]; then cp "$SRC/$f" "$DEST/"; fi
done

# ── 2. make the snapshot machine-independent ─────────────────────────────
# models.yml: literal key -> env-var name (omp resolves env names natively).
perl -pi -e 's{^(\s*apiKey:)\s*\S.*$}{$1 LAN_LLM_API_KEY}' "$DEST/agent/models.yml"
if grep -q '^[[:space:]]*apiKey:' "$SRC/agent/models.yml"; then
  if ! grep -q '^[[:space:]]*apiKey:[[:space:]]*LAN_LLM_API_KEY' "$DEST/agent/models.yml"; then
    echo "error: apiKey rewrite did not land" >&2
    abort
  fi
fi

# mcp.json: literal Basic credential -> ${LANGFUSE_API_KEY} (pi-mcp-adapter
# interpolates env vars in headers; omp loads agent/.env into the env).
LFVAL=""
if [ -f "$DEST/agent/mcp.json" ]; then
  LFVAL=$(perl -ne 'print $1 if /"Authorization"\s*:\s*"Basic\s+([^"]+)"/i' "$SRC/agent/mcp.json")
  perl -pi -e 's{("Authorization"\s*:\s*"Basic\s+)[^"]*(")}{$1\${LANGFUSE_API_KEY}$2}gi' "$DEST/agent/mcp.json"
  if [ -n "$LFVAL" ] && ! grep -qF '"Basic ${LANGFUSE_API_KEY}"' "$DEST/agent/mcp.json"; then
    echo "error: mcp.json Authorization rewrite did not land" >&2
    abort
  fi
fi

cat > "$DEST/agent/.env.example" <<'EOF'
# Copy to agent/.env (gitignored) on this machine, or let import.sh prompt
# for the values. omp also reads these from the process environment.
LAN_LLM_API_KEY=
# base64 of "<langfuse public key>:<langfuse secret key>" (Basic auth for MCP)
LANGFUSE_API_KEY=
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
# Exact-value check first: any residual copy of an original key aborts.
KEYVAL=$(sed -n 's/^[[:space:]]*apiKey:[[:space:]]*//p' "$SRC/agent/models.yml" | sed -n '1p')
KEYVAL="${KEYVAL%\"}"; KEYVAL="${KEYVAL#\"}"; KEYVAL="${KEYVAL%\'}"; KEYVAL="${KEYVAL#\'}"
[ "$KEYVAL" != "LAN_LLM_API_KEY" ] || KEYVAL=""
[ "$LFVAL" != '${LANGFUSE_API_KEY}' ] || LFVAL=""
for secret in "$KEYVAL" "$LFVAL"; do
  [ -n "$secret" ] || continue
  if grep -RIlF -- "$secret" "$DEST/agent" "$DEST/plugins" "$DEST/marketplaces.json" "$DEST/migrate-claude-agents.sh" 2>/dev/null; then
    echo "POSSIBLE SECRET STAGED (exact key value found in the files above) — aborting" >&2
    abort
  fi
done
# Shape heuristic with a left boundary so prose like "task-..." never matches.
# Filenames only — matching lines would print the secret itself.
leaked=$(grep -RIlE '(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{12,}' \
  "$DEST/agent" "$DEST/marketplaces.json" "$DEST/migrate-claude-agents.sh" 2>/dev/null || true)
if [ -n "$leaked" ]; then
  echo "POSSIBLE SECRET STAGED — aborting; found sk-like strings in:" >&2
  echo "$leaked" >&2
  abort
fi
# Literal Basic credentials (anything that is not a ${VAR} reference).
leaked=$(grep -RIlE '"Basic [A-Za-z0-9+/=]{8,}"' "$DEST/agent" 2>/dev/null || true)
if [ -n "$leaked" ]; then
  echo "POSSIBLE SECRET STAGED — aborting; found literal Basic credentials in:" >&2
  echo "$leaked" >&2
  abort
fi
soft=$(grep -RIlE '(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{12,}' "$DEST/plugins" 2>/dev/null || true)
if [ -n "$soft" ]; then
  echo "note: sk-like strings inside third-party plugin content — review before publishing:" >&2
  echo "$soft" >&2
fi

# ── 4. done ──────────────────────────────────────────────────────────────
restore_env
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
