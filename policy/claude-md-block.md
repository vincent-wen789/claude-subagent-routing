# Routing policy (v2) — CLAUDE.md block

Paste the section below into your `~/.claude/CLAUDE.md` (global) or a project `CLAUDE.md`. Adjust models and wording to taste — the structure is what matters: main thread by default, three delegation cases, a tier pinned on every spawn.

v2 since 2026-10-28. The v1 role-based table (scout / worker / judge) is kept at [claude-md-block-v1.md](claude-md-block-v1.md).

---

## Subagent routing (v2: main thread by default, delegate by context)

Splitting agents by problem type degrades like a game of telephone; split only by context. (Anthropic, "Building agents: when to fold subagents into your main agent loop", 2026-10-22.)

**Default: the main thread does the work itself.** Spawn a subagent automatically only in these three cases, and pin the model on every spawn:

1. **Independent perspective** — cold read / persona audit / blind evaluation / review → `judge`. Cold reads, single-file review and copy review: explicit `model: sonnet`. Multi-source synthesis (intel digging, competitor scans, cross-source verification, fact-checking) and architecture / cross-file review: no model param (= opus, pinned). Multi-source synthesis errors are silent — that's where the money goes.
2. **Parallel fan-out** — ≥3 branches that don't depend on each other, each returning a compact result (split research, chunked labeling). **The whole batch runs on one tier**; decide the tier before dispatching.
3. **Large-batch mechanical work** — the spec fits in a sentence or two, output dwarfs the spec, no main-thread context needed (batch renames, reformatting, chunked labeling, moving content) → `worker`; pure grunt work gets an explicit `model: haiku`.

**Unsure:** small job → do it inline. Large job (many consecutive turns of mechanical output, or reading a pile of files) → ask the user once: "I lean toward delegating to tier X because Y — OK?". **Never delegate implementation work tightly coupled to main-thread context** (code or prototype changes right after the plan was discussed).

- Read-only recon that needs a shell or a broad search → the built-in Explore agent with explicit `model: haiku`, so the main context doesn't get flooded.
- The frontier tier is never routed automatically — only on explicit user request, by name.
- If a cheap tier fails once, escalate one tier and re-dispatch. Never retry at the same tier. Say which tier you used when reporting.
- Workflow/orchestration scripts follow the same rules: mechanical stages tagged `model: 'sonnet'`/`'haiku'` + `effort: 'low'`; judgment/synthesis stages tagged `model: 'opus'`.
