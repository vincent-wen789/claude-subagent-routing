# Routing policy — CLAUDE.md block

Paste the section below into your `~/.claude/CLAUDE.md` (global) or a project `CLAUDE.md`. Adjust models and wording to taste — the structure is what matters: role → model × effort, plus the escalation and no-inherit rules.

---

## Subagent model routing (orchestrator mode)

Main thread = the brain (judgment / planning / synthesis); subagents are pinned to cheap tiers by role. **Gate zero: don't delegate what you can do inline** — spawning has overhead, and multi-agent runs cost several times solo work.

| Work type | Agent | Model | Effort |
|---|---|---|---|
| Read-only recon: scan files / search code / read docs / summarize current state | `scout` | haiku | low |
| Mechanical execution: plan already decided, batch edits, write-to-spec | `worker` | sonnet | medium |
| Judgment: independent review / design / complex research | `judge` | opus (pinned in frontmatter) | inherit session |

- **Pin the judgment tier explicitly — never "inherit the main thread"**: if the main thread runs a frontier model, inheritance silently doubles the price. (Measured over the 6 days this table ran with an "inherit" judgment tier: frontier-model subagents were 31% of subagent tokens and 73% of subagent spend.) Only pinning takes effect automatically; a rule that depends on someone remembering is not a rule. The `judge` agent pins opus in its frontmatter, so a forgotten tag can no longer leak.
- The frontier tier is never routed automatically — only on explicit user request, by name.
- Split the judgment tier: heavy judgment (architecture, cross-file review, open-ended design, multi-source synthesis) → `judge` as-is (default opus); light judgment (single-file review, copy review, two-way choices, small verifiable research) → `judge` with an explicit sonnet tag; unsure → leave untagged (= opus), and say which tier you used when reporting.
- Subagents spawned on the assistant's own initiative follow this table too — that's where most of the volume is. The built-in Explore agent gets an explicit haiku tag; read-only recon that needs a shell goes to Explore instead of scout (scout has no Bash).
- Mixed tasks: split into segments — recon → scout, judgment → main thread, execution → worker. If splitting isn't worth it, route the whole thing at the heaviest segment's tier.
- If a cheap tier fails once, escalate one tier and re-dispatch. Never retry at the same tier.
- Workflow/orchestration scripts follow the same table: mechanical stages tagged `model: 'sonnet'`/`'haiku'` + `effort: 'low'`; judgment/synthesis stages tagged `model: 'opus'`.
