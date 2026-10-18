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
| `agent/agents/` | task agents |
| `agent/skills/`, `agent/commands/` | feature-dev skill + command |
| `plugins/` | superpowers + voltagent-* marketplace plugins (full tree incl. cache) |
| `marketplaces.json` | marketplace registry |
| `migrate-claude-agents.sh` | helper used to migrate Claude agents |

Never committed: `agent/.env` (the real API key), `agent.db` (credential
store), sessions, history, model caches, `natives/` — all machine-local or
regenerable.

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
./import.sh                     # -> ~/.omp (prompts for the API key once)
# or non-interactive:
LAN_LLM_API_KEY=sk-... ./import.sh
# or into a custom omp home (also how the scripts test themselves):
./import.sh /path/to/omp-home
```

Then verify:

```sh
omp config path
omp models lan-llm --json    # GLM-5.3-Flash-EXL3, 1M context window
omp plugin list              # superpowers + voltagent-*
```

## Secrets model

The repo never holds the real key. `agent/models.yml` references the
environment-variable name `LAN_LLM_API_KEY` (omp resolves env names natively);
the value lives in `agent/.env` (gitignored) on each machine. import.sh writes
it from the environment or an interactive prompt. Rotation: change the key at
the gateway, then update `agent/.env` on each machine (no repo change).

## Update flow

1. Change config on any machine (`/settings`, `omp plugin install`, ...)
2. `./export.sh --commit && git push`
3. On other machines: `git pull && ./import.sh`

## Portability

Absolute home paths in plugin metadata (`marketplaces.json`,
`installed_plugins.json`, `node_modules` symlinks) are stored as
`__OMP_HOME__` placeholders and rewritten to the local home directory on
import, so the repo works under any username on Linux and macOS.
