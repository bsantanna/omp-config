# Endpoint Env Vars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the LLM gateway and Langfuse MCP endpoints overridable via env vars, defaulting to today's btech URLs.

**Architecture:** `mcp.json` stores `${LANGFUSE_MCP_URL:-<default>}` (pi-mcp-adapter resolves at runtime). `models.yml` stores `__LAN_LLM_BASE_URL__`; `import.sh` renders it (env → target `agent/.env` → default), `export.sh` restores the placeholder.

**Tech Stack:** bash, perl (literal replace), omp 18.15.0, pi-mcp-adapter.

**Spec:** `docs/superpowers/specs/2026-11-14-endpoint-env-vars-design.md`

## Global Constraints
- `DEFAULT_LAN_LLM_BASE_URL=https://llm-gw-eu.btech.software/v1`
- `DEFAULT_LANGFUSE_MCP_URL=https://langfuse.btech.software/api/public/mcp`
- Placeholder token: `__LAN_LLM_BASE_URL__`; mcp url form: `${LANGFUSE_MCP_URL:-https://langfuse.btech.software/api/public/mcp}`
- No behavior change when no env var is set. No prompting for URLs.
- Default constants live at the top of each script as `DEFAULT_*` vars.
- Work on branch `feat/endpoint-env-vars`; the existing uncommitted `agent/models.yml` modelOverrides removal is kept and committed with Task 1.
- The repo has no test suite (shell tests were removed deliberately); verification scripts live in the session scratchpad, not the repo.

## Review Focus
1. Re-export after import: live `models.yml` holds a rendered URL → export must restore the placeholder, not commit a custom URL.
2. Live `mcp.json` already containing `${LANGFUSE_MCP_URL:-…}` → export leaves it byte-identical (idempotent).
3. Target `agent/.env` has `LAN_LLM_BASE_URL=` with a value containing `/` or `&` → rendered literally (no regex/sed delimiter breakage).
4. Env var set but empty → treated as unset (default used), not an empty `baseUrl`.
5. Re-import onto an already-rendered target → still renders from the repo copy (placeholder), no leftover placeholder.

---

### Task 1: export.sh — restore placeholders, extend .env.example

**Files:**
- Modify: `export.sh` (section 2 rewrites; `.env.example` heredoc; header comment)
- Modify: `agent/models.yml:3`, `agent/mcp.json:4`, `agent/.env.example` (regenerated)

**Interfaces:**
- Produces: repo `models.yml` line `    baseUrl: __LAN_LLM_BASE_URL__`; repo `mcp.json` `"url": "${LANGFUSE_MCP_URL:-<default>}"`.

- [ ] **Step 1: Write verification** `scratchpad/verify-export.sh`: fake omp home with `config.yml`, `models.yml` (`baseUrl: https://custom.example/v1`), `mcp.json` (literal `https://lf.example/api/public/mcp`, `Basic abcdefghij`); copy repo to scratch dir, run its `export.sh <fakehome>`; assert `grep -qx '    baseUrl: __LAN_LLM_BASE_URL__'`, mcp.json contains the exact `${LANGFUSE_MCP_URL:-https://langfuse.btech.software/api/public/mcp}` string, `custom.example` and `lf.example` absent, `.env.example` contains `LAN_LLM_BASE_URL=` and `LANGFUSE_MCP_URL=` lines (commented defaults). Second case (Review Focus 2): live mcp.json already in `${…}` form → output identical.
- [ ] **Step 2: Run it** — expect FAIL (baseUrl still custom).
- [ ] **Step 3: Implement** in `export.sh`: perl `s{^(\s*baseUrl:)\s*\S.*$}{$1 __LAN_LLM_BASE_URL__}`; perl rewrite of `"url": "<value not starting with ${>"` → `${LANGFUSE_MCP_URL:-$DEFAULT_LANGFUSE_MCP_URL}` (pass default via `$ENV`); `abort` if either expected string missing after rewrite (only when source had the field). Add both vars to the `.env.example` heredoc as `# LAN_LLM_BASE_URL=<default>` / `# LANGFUSE_MCP_URL=<default>` with a one-line comment each.
- [ ] **Step 4: Run it** — expect PASS. Then update repo files: set `agent/models.yml` and `agent/mcp.json` to the stored forms, `agent/.env.example` to the heredoc output.
- [ ] **Step 5: Commit** `export.sh agent/` — `feat: store endpoints as env-var placeholders on export`.

### Task 2: import.sh — render LAN_LLM_BASE_URL, self-check

**Files:**
- Modify: `import.sh` (after section 3 `.env` handling, before section 4; section 4 self-check; header comment)

**Interfaces:**
- Consumes: placeholder `__LAN_LLM_BASE_URL__` from Task 1.
- Produces: `resolve_base_url` precedence: non-empty process env → `LAN_LLM_BASE_URL=` line in `$TARGET/agent/.env` (last match, value verbatim) → `DEFAULT_LAN_LLM_BASE_URL`.

- [ ] **Step 1: Write verification** `scratchpad/verify-import.sh` (stub `omp` on PATH as no-op so the install step passes; `LAN_LLM_API_KEY=x LANGFUSE_API_KEY=y`): cases — (a) no var → rendered `baseUrl: https://llm-gw-eu.btech.software/v1`; (b) `LAN_LLM_BASE_URL=https://a.example/v1?x=1&y=/z` → exact literal; (c) var unset, target `.env` has `LAN_LLM_BASE_URL=https://b.example/v1` → that value; (d) `LAN_LLM_BASE_URL=` empty → default; (e) re-import on rendered target → no `__LAN_LLM_BASE_URL__` remains; mcp.json copied unchanged in all cases.
- [ ] **Step 2: Run it** — expect FAIL (placeholder left in target).
- [ ] **Step 3: Implement**: resolve per precedence, render with `perl -pi` literal `split/join` (same idiom as `__OMP_HOME__`); add self-check: `grep -q '__LAN_LLM_BASE_URL__'` in target models.yml → `status=1` with message. Print `using LAN_LLM_BASE_URL=<value> (<source>)`.
- [ ] **Step 4: Run it** — expect PASS; also run `bash -n import.sh export.sh`.
- [ ] **Step 5: Commit** `import.sh` — `feat: render LAN_LLM_BASE_URL on import`.

### Task 3: README

**Files:**
- Modify: `README.md` (What travels table rows for models.yml/mcp.json; Load examples; Verify block; new "Endpoints" subsection after "Secrets model")

- [ ] **Step 1:** Table: models.yml → "`lan-llm` gateway provider (key and base URL as env names)"; drop "+ model overrides". mcp.json → mention `${LANGFUSE_MCP_URL}`.
- [ ] **Step 2:** Verify block: replace `# GLM-5.3-Flash-EXL3, 1M context window` with `# models discovered from the gateway`.
- [ ] **Step 3:** Add "Endpoints" section: table of both vars with defaults; LANGFUSE_MCP_URL is resolved at runtime (set in env or `agent/.env`, restart omp); LAN_LLM_BASE_URL is rendered by import.sh (precedence env → `agent/.env` → default), so changing it needs a re-import. Add a non-interactive example `LAN_LLM_BASE_URL=https://… ./import.sh`.
- [ ] **Step 4:** `grep -n 'GLM\|override' README.md` → no stale model-override mentions.
- [ ] **Step 5: Commit** `README.md docs/superpowers/` — `docs: document endpoint env vars, drop model override mention`.
