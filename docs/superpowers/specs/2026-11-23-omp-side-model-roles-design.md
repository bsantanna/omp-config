# omp side-model roles on the lan-llm endpoint (design, 2026-11-23)

## Why
Every omp role runs on the one `lan-llm/DeepSeek-V4.1-Flash-1017` endpoint (TensorFold, Mia's 2x DGX Spark
recipe, via LiteLLM). Only `default` was assigned, at `defaultThinkingLevel: high`, so side jobs (titles, job
captions, commit messages, judge calls) also thought, and omp's default "reasoning off" (`reasoning_effort: low`)
is "think briefly" on TensorFold: job captions hit their 120-token cap while still thinking and came back empty.

## Goals
- Side jobs that need no deliberation run with thinking truly off (TensorFold `reasoning_effort: "none"`).
- Main work keeps `high`; an explicit deep-reasoning role exists.
- Vision stays on the same model (omp already reports `input: [text, image]`).
- Settings live in `~/.omp/agent/` and travel through this repo (export/import).

## Non-goals
Compaction thresholds, advisor/memory features (off), server-side changes.

## Anti-goals
Lower quality on the main coding turns; secrets in the repo.

## Approaches
- **Per-role `model:level` suffixes in `modelRoles` + provider `compat.reasoningDisableMode: none-effort` (picked).**
  omp 18.15 parses a thinking suffix per role selector; the compat line makes `off` reach TensorFold as `none`.
- A LiteLLM "-nothink" model alias (terraform on moon): rejected; the fault was omp's off-mode, not the server.
- Global `defaultThinkingLevel` change: rejected; it would lower the main turns too.

## Design
`config.yml` `modelRoles` (M = `lan-llm/DeepSeek-V4.1-Flash-1017`):

| role | value | reason |
|---|---|---|
| default, plan, task | `M` (inherits `high`) | real coding/planning work |
| slow | `M:max` | explicit deep-reasoning role (recipe warns `max` can loop in agent jobs; used deliberately) |
| smol, commit, tiny, widget, judge | `M:off` | titles, captions, commit messages, yes/no judgements |
| vision | `M:off` | image description is perception |

`models.yml` provider `lan-llm`: `compat: { reasoningDisableMode: none-effort }`.
Verification: `omp config get modelRoles`; jupiter's log shows `thinking=False effort=none` for an `:off` role
request and `effort=high` for the default.

## Left to the builder
Exact YAML layout; whether export.sh carries the new keys unchanged (it must; check the diff).
