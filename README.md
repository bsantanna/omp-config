# omp-config

Portable Oh My Pi (omp) configuration: agents, plugins, skills, commands, and
provider setup — synced from `~/.omp` and restorable on any Linux/macOS
machine. Requires `omp` (https://omp.sh) and `git` (plus `perl`, present on
both platforms by default).

## What travels

| Path | Content |
|---|---|
| `agent/config.yml` | global omp settings |
| `agent/models.yml` | `lan-llm` gateway provider (key as env name, base URL as `__LAN_LLM_BASE_URL__` placeholder) |
| `agent/mcp.json` | MCP servers (Langfuse; URL as `${LANGFUSE_MCP_URL:-…}`, credential as `${LANGFUSE_API_KEY}`) |
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
# or against a different gateway (see "Endpoints"):
LAN_LLM_BASE_URL=https://my-gateway.example/v1 ./import.sh
# or into a custom omp home (also how the scripts test themselves):
./import.sh /path/to/omp-home
```

Then verify:

```sh
omp config path
omp models lan-llm --json    # models discovered from the gateway
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

## Endpoints

Both endpoints default to the btech hosts and can be overridden per machine:

| Variable | Default | Resolved |
|---|---|---|
| `LAN_LLM_BASE_URL` | `https://llm-gw-eu.btech.software/v1` | by import.sh, into `agent/models.yml` |
| `LANGFUSE_MCP_URL` | `https://langfuse.btech.software/api/public/mcp` | at runtime, by pi-mcp-adapter |

omp does not expand env vars in `models.yml` `baseUrl`, so the repo stores
`__LAN_LLM_BASE_URL__` and import.sh renders it from the `LAN_LLM_BASE_URL`
environment variable, then a `LAN_LLM_BASE_URL=` line in `agent/.env`, then
the default. A value passed via the environment is saved to `agent/.env`
(existing entries are never overwritten), so later plain `./import.sh` runs
keep it; changing the gateway afterwards means editing `agent/.env` and
re-importing. `mcp.json` stores `${LANGFUSE_MCP_URL:-<default>}`, so setting
`LANGFUSE_MCP_URL` in the environment or `agent/.env` takes effect on the next
omp start. On export, only the `lan-llm` provider's `baseUrl` and the
`langfuse` server's literal `url` are rewritten to these forms; other
providers and MCP servers keep their URLs.

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
