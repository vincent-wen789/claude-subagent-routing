# claude-subagent-routing

**English** | [中文](README.zh.md) | [日本語](README.ja.md)

Static model routing for Claude Code subagents: one policy table, two pinned agents, one deny hook (~15 lines of logic). No classifier, no proxy, no framework — and 26 days of single-user production receipts (n=1).

**The receipts first** (Jul 3 – Aug 3: a 6-day pre-routing baseline, then 26 days on the system — 497M subagent tokens over those 26 days, one user, mixed real workload; unit costs at period prices, Sonnet $2/$10 throughout):

| Metric | Before (Jul 3–8) | Pinned (Jul 9–15) | Hardened (Jul 16–Aug 3) |
|---|---|---|---|
| Unit cost, $ per M in+out tokens | 3.98 | 1.94 | **1.31** |
| Frontier model (Fable) share of subagent tokens | 41.5% | 29% | **0.28%** (7 assistant turns in 19 days, all from by-name spawns) |
| `scout` avg output per call | — | 282 tok | 167 tok (`effort: low`, −41%) |

**Who this is for:** you run Claude Code with an Opus or Fable main thread, and work gets delegated to subagents — in my hardened window that was ~15% of total in+out token flow, billed at whatever model each spawn lands on. If your main thread is Sonnet-only, star it for the method; the dollars won't move much. Thirty seconds to see your own mix before installing anything: [audit §2](audit/audit-commands.md) is one copy-paste command.

Cumulative: roughly **$1,100 less spend** than the pre-routing mix would have cost — $882 actual vs. a $1,978 counterfactual, where the counterfactual is just 497M tokens × the $3.98 baseline unit cost. (A volume-held counterfactual: it assumes the old mix would have burned the same 497M tokens. Deny-and-reissue overhead and any change in spawn habits aren't modeled — treat $1,100 as order-of-magnitude, not an invoice. The $882 side is the summed actual spend of the three windows at period prices; volume wasn't spread evenly across windows, so you can't back it out from the unit-cost rows alone.)

Four measurement notes, because the receipts only count if you can audit them:

- **Sonnet ran at its limited-time $2/$10 in this window** (list returns to $3/$15 on Sep 1, 2026). The audit doc ships both prices; reproduce with the period prices.
- **Cache writes are charged at the 1-hour-TTL 2× multiplier** (swap in 1.25× for 5-minute TTL). The before/after ratio doesn't care — the same multiplier sits on both sides.
- **Unit cost = total spend over total tokens** (input, output, and cache on both sides of the fraction), so it also moves with conversation shape, not just model mix. The frontier-share row — computed on in+out tokens only — is the routing-only signal; the two move together here.
- **Quality is self-report only** — I didn't instrument escalation counts, so the honest phrasing is: over 26 days of daily use I couldn't tell the difference from running everything on one model.

I'm on a subscription, so all dollar figures are API-list-price quota proxies, not an invoice. The ratios are the point.

The model shares, window unit costs, and leak checks are reproducible from your own disk — see [audit/audit-commands.md](audit/audit-commands.md). (The per-agent `scout` row came from session-level inspection; transcripts don't tag sidechain turns with the agent name.)

## The default nobody audits

Claude Code subagents inherit the session model unless a model is pinned in the agent definition or passed explicitly at spawn time. On a Sonnet main thread that default is harmless. On an Opus or Fable main thread, it means every "go grep that for me" fan-out bills at frontier rates.

This is not a niche complaint. [anthropics/claude-code#27665](https://github.com/anthropics/claude-code/issues/27665) documents a Max subscriber putting **93.8% of tokens through Opus over 17 days ($1,246 at list prices)** because nothing in the default pipeline routes work down-tier — and the first remedy it proposes is exactly this repo's subject: stop defaulting subagents to the expensive session model. Open, no official response, as of 2026-08-03.

My version of the incident: the routing table shipped Jul 9 with one soft spot — the judgment tier said "inherit the main thread", written back when the main thread was Opus. By then my daily driver had moved to Fable 5 ($10/$50 — 2x Opus). Nothing broke, nothing warned. The first acceptance audit, six days in, found Fable subagents at **31% of subagent tokens and 73% of subagent spend** for that window — down from the fully unrouted baseline (41.5% of tokens, the table's Before column), but still the single biggest line item, riding on one stale assumption. Same day: judgment tier pinned to explicit opus, hook added. (The table's 29% for the Pinned window is the full seven days — day seven, the first day behind the pins, pulls the average below the day-six audit's 31%.)

## Prior art, honestly

This niche has real projects in it. What I couldn't find anywhere: production numbers.

| Project | What it is | Enforcement | Extra classifier | Published measurements |
|---|---|---|---|---|
| [pilotfish](https://github.com/Nanako0129/pilotfish) | 8 role agents, models pinned in frontmatter, orchestration policy | None — advisory; README states install does not guarantee delegation | No | Cites vendor benchmarks, not own production data |
| [oh-my-claudecode](https://github.com/yeachan-heo/oh-my-claudecode) | Large multi-agent orchestration suite | Not documented | No | Advertises 30–50% savings; no data I could find |
| [claude-model-router-hook](https://github.com/tzachbon/claude-model-router-hook) | 3 hooks; classifies prompts, rewrites spawns | Rewrites spawn params | Keyword heuristics + optional Haiku fallback | None |
| [claude-model-router](https://github.com/junoseong/claude-model-router) | API router + a deny-based Claude Code hook | Deny + re-issue | LLM (Haiku) classifier | Synthetic 1,000-prompt cost model + 17 live prompts |
| Auditors ([ccost](https://github.com/toolsu/ccost), [token-dashboard](https://github.com/nateherkai/token-dashboard), …) | Cost analytics over local transcripts | — | — | Measure spend; know nothing about your policy |

*Surveyed 2026-08-03 from each project's public README — point-in-time claims; corrections welcome via issue.*

So: frameworks route but don't enforce, hook routers enforce but bring a classifier, auditors measure but don't route. This repo is the missing combination — **policy + enforcement + measurement, no classifier** — plus the receipts.

## The system: three layers × two dimensions

**Layer 1 — the routing table** ([policy/claude-md-block.md](policy/claude-md-block.md)), pasted into `CLAUDE.md`:

| Work type | Agent | Model | Effort |
|---|---|---|---|
| Read-only recon (scan / search / read / summarize) | [`scout`](agents/scout.md) | haiku | low |
| Mechanical execution (plan decided, just hands) | [`worker`](agents/worker.md) | sonnet | medium |
| Judgment (review / design / research) | general-purpose | explicit opus | session |

Models are pinned in agent frontmatter, so the table holds even when nobody is thinking about it. The second dimension matters more than it looks: `effort: low` alone cut scout's output tokens 41% with no perceived quality loss on recon work.

**Layer 2 — judgment-tier split, done by the orchestrator itself.** Light judgment (single-file review, copy review, two-way choices) gets tagged sonnet; heavy judgment (architecture, cross-file review, open-ended design) gets opus; unsure defaults to opus. This is the "dynamic routing" part of the system, and it needs no infrastructure at all — see below.

**Layer 3 — the mechanical gate** ([hooks/agent-model-guard.sh](hooks/agent-model-guard.sh)). A PreToolUse hook on the Agent tool: any spawn that neither uses a pinned agent nor passes an explicit `model` is **denied**, with the routing table in the deny reason. The orchestrator reads it and re-issues the spawn with a model attached. Rules prevent habit; the gate prevents mistakes.

Escalation rule that keeps the cheap tiers honest: if a cheap tier botches a task once, re-dispatch one tier up. Never retry at the same tier.

## Install

Three files, one settings entry, one policy block. From a clone of this repo (the hook needs `jq` — `command -v jq` to check):

```bash
mkdir -p ~/.claude/agents ~/.claude/hooks
cp agents/scout.md agents/worker.md ~/.claude/agents/
cp hooks/agent-model-guard.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/agent-model-guard.sh
```

In `~/.claude/settings.json` — **merge into your existing `hooks.PreToolUse` array if you have one; don't paste over the file**:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/agent-model-guard.sh\"", "timeout": 5 }]
      }
    ]
  }
}
```

(An absolute path in `command` is the battle-tested form; the `timeout` keeps a wedged hook from ever stalling a spawn.)

Then paste the policy block from [policy/claude-md-block.md](policy/claude-md-block.md) into your `CLAUDE.md`. The `effort` frontmatter key is documented in the [official sub-agents docs](https://code.claude.com/docs/en/sub-agents).

Notes that save you a bug report:

- **Restart Claude Code after installing** — agent definitions load at session start.
- **Leave `CLAUDE_CODE_SUBAGENT_MODEL` unset** — it globally overrides per-agent frontmatter, which would silently defeat the pins.
- **Agent names resolve project-first.** If a project defines its own `scout`/`worker`, that definition wins over `~/.claude/agents/`. Keep these names unique in your setup, and if you add your own pinned agents, extend the hook's allowlist (`scout|worker|fork`) to match.
- **The hook validates the requested spawn, not the resolved model.** It closes the "forgot to tag" failure mode — which in my measurements was the entire leak — not every conceivable misconfiguration.

Smoke test: in any session, ask Claude to spawn a general-purpose subagent *without* specifying a model. Expected: the spawn is denied, the deny reason echoes the routing table, and Claude re-issues it with a model attached. Tested on Claude Code 2.1.210, Aug 2026. If it never denies: check `jq` is installed, the script path in settings.json resolves, and the matcher is exactly `Agent` — hook payload schemas can drift between versions, so diff against the changelog if you're far from 2.1.210. If it denies but Claude doesn't re-issue, that's model compliance, not the hook. Failure mode is open by design: a crashing hook surfaces an error and the spawn proceeds — worst case is stock behavior, not a bricked session.

That's the whole install. No daemon, no proxy, no npm.

## The method (what I'd do again)

1. **Audit the defaults.** Every "inherit / default" behavior hides an assumption that fails silently when the environment changes. The first cost lever is not switching to a cheaper model — it's finding the expensive default that's already running.
2. **Pin beats discretion.** The savings came from deleting decisions, not making better ones. A rule that requires remembering is not a rule.
3. **Gate the mistakes.** Prompt-level rules (CLAUDE.md) are reliable but soft. Fifteen lines of hook weld the "forgot to tag" failure mode shut.
4. **Close the loop with data.** Define metrics before shipping (unit cost, leak count, model shares), re-measure with the same commands, and dissect counterintuitive signals before concluding. Example: sonnet's average output per turn jumped mid-run — not an effort-tier failure, but light-judgment tasks joining the sonnet lane and changing the mix. Dissect the population before blaming the knob.

## What I deliberately didn't build

- **No classifier.** Both hook routers in the table above add one (keyword heuristics or an extra Haiku call) to decide task difficulty. But the orchestrator *wrote the task prompt* — it already knows whether the work is recon, mechanical, or judgment. Static routing plus the orchestrator's own tier-split captures the value; a classifier duplicates a judgment that is already free, and adds a misclassification surface.
- **No rewrite-style enforcement.** Deny-and-reissue keeps the orchestrator in the loop and composes safely with other hooks; rewriting spawn params via `updatedInput` has undocumented merge order when multiple hooks fire (per the router-hook project's own README). Convergent evidence: junoseong's deny-based hook measured **25.3k → 11.4k tokens** on a deny-retry test task.
- **No finer tiers.** Post-hardening, the remaining headroom is coin-picking. Every added tier adds classification burden and misroute surface for cents of upside.
- **No cross-provider proxy.** Tools like [claude-code-router](https://github.com/musistudio/claude-code-router) solve a different problem (swapping backends). This system stays inside one vendor and one subscription, which is exactly why the numbers above are clean.

## Known gaps

- **In-workflow `agent()` calls bypass the Agent hook** (PreToolUse never fires for them). Soft-constrained by the policy block only. Measured leakage: 7 calls ≈ $6 over 19 days — not worth a gate.
- **`fork` agents are exempt by design** — inheritance is their semantic; the model param is a no-op.
- **Open question:** the opus tier still carries ~52% of subagent tokens. Task mix, or under-use of the light-judgment split? Next re-measure will say.
- **September re-test planned:** Sonnet's limited-time pricing ($2/$10) ends Sep 1 → $3/$15. Unit cost will mechanically rise ~20%. That's list price, not routing regression — flagging it now so the future number isn't misread.
- Model aliases (`opus`, `sonnet`, `haiku`) resolve forward: mid-run, the `opus` alias picked up a newer Opus at the same price — a free upgrade here, but pin exact model IDs if you need determinism.

## License

[MIT](LICENSE) · Questions and corrections: open an issue. I'm [@vinentW789](https://x.com/vinentW789) on X.
