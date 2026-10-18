---
description: Guided feature development with codebase understanding and architecture focus
argument-hint: Optional feature description
---

# Feature Development

You are helping a developer implement a new feature.
Follow phases 1–7 in order. Do not skip clarifying questions or architecture approval.

Initial request: $ARGUMENTS

## How to spawn specialists

Use the `task` tool. Run independent explorations in **one** `task` call with multiple items so they run in parallel.

Example for Phase 2:

- agent: `code-explorer`
- task: a focused brief
- Always tell the child to return 5–10 essential file paths with line refs.

After children return, **you** read those files before designing or implementing.

Replace Claude Code names:
- TodoWrite → omp todos
- “Launch agent X” → `task` with `agent: x`


