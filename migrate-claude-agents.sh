#!/usr/bin/env bash
# Migrate Claude Code marketplace plugin subagents into omp's native layout.
#
# Why: omp (oh-my-pi) discovers task subagents from `<plugin-root>/agents/`
# (task/discovery.ts joins plugin.path with "agents"). Claude marketplace
# plugins like voltagent-subagents ship agent files at the pack ROOT and list
# them in .claude-plugin/plugin.json `agents: [...]` — a manifest key omp
# ignores. Without this sync, installed packs expose zero subagents.
#
# What: for every omp-installed marketplace pack under
# ~/.omp/plugins/cache/plugins/<marketplace>___<plugin>___<version>/, copy the
# root-level agent *.md files (excluding README.md) into <pack>/agents/.
#
# Re-run after `omp plugin upgrade` — upgrades create fresh versioned pack
# directories without the agents/ subdir. Idempotent: copies overwrite.
set -euo pipefail

plugin_cache="${OMP_PLUGIN_CACHE:-$HOME/.omp/plugins/cache/plugins}"
migrated=0

for pack in "$plugin_cache"/*/; do
	pack="${pack%/}"
	# Only claude-plugin-format packs (marketplace installs).
	[ -d "$pack/.claude-plugin" ] || continue
	mkdir -p "$pack/agents"
	count=0
	for f in "$pack"/*.md; do
		base="$(basename "$f")"
		[ "$base" = "README.md" ] && continue
		cp -f "$f" "$pack/agents/$base"
		count=$((count + 1))
	done
	migrated=$((migrated + count))
	printf '%s: %s agents\n' "$(basename "$pack")" "$count"
done

printf 'Total: %s agent files synced\n' "$migrated"
