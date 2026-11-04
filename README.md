# omp-config

Portable Oh My Pi (omp) configuration: agents, plugins, skills, commands, and
provider setup — synced from `~/.omp` and restorable on any Linux/macOS
machine. Requires `omp` (https://omp.sh) and `git` (plus `perl`, present on
both platforms by default).

## What travels

| Path | Content |
|---|---|
| `agent/config.yml` | global omp settings |
| `agent/models.yml` | `lan-llm` gateway provider + model overrides (key as env name) |
| `agent/mcp.json` | MCP servers (Langfuse; credential as `${LANGFUSE_API_KEY}`) |
| `agent/agents/` | task agents |
| `agent/skills/`, `agent/commands/` | feature-dev skill + command, Cloudflare `security-audit` skill (vendored, pinned) |
| `plugins/` | superpowers, pi-mcp-adapter, voltagent-* marketplace plugins (manifests, `bun.lock`, marketplace cache; npm deps are reinstalled on import) |
| `marketplaces.json` | marketplace registry |
| `migrate-claude-agents.sh` | helper used to migrate Claude agents |

Never committed: `agent/.env` (the real API keys), `agent.db` (credential
store), sessions, history, model caches, `natives/`, npm-installed plugin deps
(`plugins/node_modules` except omp's marketplace symlinks; they include
platform-specific native binaries) — all machine-local or regenerable.

## Export (source machine)

```sh
./export.sh            # sync ~/.omp -> repo
./export.sh --commit   # sync + git commit
```

Re-runnable anytime; regenerates the snapshot from the live config.

## Load (new workstation)

```sh
git clone git@github.com:bsantanna/omp-config.git
cd omp-config
./import.sh                     # -> ~/.omp (prompts for missing keys once)
# or non-interactive:
LAN_LLM_API_KEY=sk-... LANGFUSE_API_KEY=<base64 pk:sk> ./import.sh
# or into a custom omp home (also how the scripts test themselves):
./import.sh /path/to/omp-home
```

Then verify:

```sh
omp config path
omp models lan-llm --json    # GLM-5.3-Flash-EXL3, 1M context window
omp plugin list              # superpowers, pi-mcp-adapter, voltagent-*
```

import.sh reinstalls plugin npm deps from `plugins/bun.lock`
(`BUN_BE_BUN=1 omp install --frozen-lockfile`), so it needs network access.

## Secrets model

The repo never holds real keys. `agent/models.yml` references the
environment-variable name `LAN_LLM_API_KEY` (omp resolves env names natively),
and `agent/mcp.json` sends `Authorization: Basic ${LANGFUSE_API_KEY}`
(pi-mcp-adapter interpolates env vars in headers). `LANGFUSE_API_KEY` is
`base64("<public key>:<secret key>")` of a Langfuse API key pair. The values
live in `agent/.env` (gitignored) on each machine, which omp loads at startup.
import.sh adds any missing key from the same-named environment variable or an
interactive prompt, and never overwrites existing entries. export.sh replaces
literal credentials with the env-var references and aborts if any original
value survives. Rotation: change the key upstream, then update `agent/.env` on
each machine (no repo change).

## Update flow

1. Change config on any machine (`/settings`, `omp plugin install`, ...)
2. `./export.sh --commit && git push`
3. On other machines: `git pull && ./import.sh`

## Portability

Absolute home paths in plugin metadata (`marketplaces.json`,
`installed_plugins.json`, `node_modules` symlinks) are stored as
`__OMP_HOME__` placeholders and rewritten to the local home directory on
import, so the repo works under any username on Linux and macOS.

## License

MIT — see [LICENSE](LICENSE).
