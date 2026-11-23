# omp side-model roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assign every omp chat role to the lan-llm DeepSeek endpoint with the right thinking level, make `off` reach TensorFold as real thinking-off, and carry it into this repo.

**Architecture:** Edit the live config in `~/.omp/agent/` on water (the repo's source of truth is the live home: `export.sh` copies it), verify on jupiter's log, then `./export.sh` and review the diff.

**Tech Stack:** omp 18.15.0 (water), YAML config, this repo's export.sh.

**Spec:** `docs/superpowers/specs/2026-11-23-omp-side-model-roles-design.md`

## Global Constraints
- Model selector M = `lan-llm/DeepSeek-V4.1-Flash-1017`; role values exactly as the spec table: default/plan/task = `M`; slow = `M:max`; smol/commit/tiny/widget/judge/vision = `M:off`.
- `models.yml` provider `lan-llm` gains `compat: { reasoningDisableMode: none-effort }`; nothing else in it changes.
- No secret leaves `agent/.env`; export.sh's secret checks must pass.

## Review Focus
- An unknown role key or bad suffix silently ignored by omp -> `omp config get modelRoles --json` must echo all 11 entries.
- `:off` still sending `reasoning_effort: low` (compat not picked up) -> jupiter must log `thinking=False effort=none`.
- Main turns accidentally lowered -> a default-role request must log `effort=high`.
- export.sh rewriting the new `compat` block or dropping it -> repo diff of `agent/models.yml` shows only the added compat lines.
- Neptune (omp 19.1.0) not yet carrying these settings -> stated in the hand-off, not changed here.

---

### Task 1: Live config on water + verification

**Files:**
- Modify: `~/.omp/agent/config.yml` (`modelRoles` block), `~/.omp/agent/models.yml` (`lan-llm` provider)

- [ ] **Step 1: Back up** both files to `*.bak-2026-11-23`.
- [ ] **Step 2: Write** the `modelRoles` block and the `compat` lines per Global Constraints (comment the compat line with the TensorFold reason, as on neptune).
- [ ] **Step 3: Verify parsing.** Run `omp config get modelRoles --json` -> 11 roles with the exact values above.
- [ ] **Step 4: Verify on the server.** Run `omp -p --no-session --no-title --no-extensions --model "lan-llm/DeepSeek-V4.1-Flash-1017:off" "Reply with the single word OK."` and the same with the default model (no suffix). Expected in jupiter's `docker logs`: first `thinking=False effort=none`, second `thinking=True effort=high`.

### Task 2: Carry into the repo

**Files:**
- Modify (via export.sh): `agent/config.yml`, `agent/models.yml`

- [ ] **Step 1: Run** `./export.sh` (no `--commit`). Expected: exit 0, no "POSSIBLE SECRET" abort.
- [ ] **Step 2: Review** `git diff --stat` and `git diff agent/config.yml agent/models.yml`: only the roles and compat lines; anything else export pulled in is reported to the user, not committed blindly.
- [ ] **Step 3: Commit** spec, plan and config on `feat/side-model-roles`:
  `git commit -m "feat: per-role thinking levels for the lan-llm endpoint"` (with the attribution trailer).
