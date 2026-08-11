# claude-subagent-routing

**English** | [中文](README.zh.md) | [日本語](README.ja.md)

Static model routing for Claude Code subagents: one policy table, two pinned agents, one deny hook (~15 lines of logic). No classifier, no proxy, no framework — and 26 days of single-user production receipts (n=1).

New to this corner of Claude Code? The one-breath version: while working, Claude Code quietly hires helper AIs — *subagents* — for side jobs like searching your codebase or applying bulk edits. By default, every helper bills at whatever model your main session runs. If that's an expensive model, you're paying senior rates for intern work, and nothing on screen tells you. This repo pins the intern work to intern-priced models and puts a gate in front of the mistake. How you use Claude doesn't change; the billing does.

**The receipts first** (Jul 3 – Aug 3: a 6-day pre-routing baseline, then 26 days on the system — 497M subagent tokens, one user, mixed real workload; fine print lives with the [audit commands](audit/audit-commands.md)):

| Metric | Before (Jul 3–8) | Pinned (Jul 9–15) | Hardened (Jul 16–Aug 3) |
|---|---|---|---|
| Unit cost, $ per M in+out tokens | 3.98 | 1.94 | **1.31** |
| Frontier model (Fable) share of subagent tokens | 41.5% | 29% | **0.28%** (7 assistant turns in 19 days, all from by-name spawns) |
| `scout` avg output per call | — | 282 tok | 167 tok (`effort: low`, −41%) |

**Who this is for:** you run Claude Code with an Opus or Fable main thread, and work gets delegated to subagents — in my hardened window that was ~15% of total in+out token flow, billed at whatever model each spawn lands on. If your main thread is Sonnet-only, star it for the method; the dollars won't move much. Thirty seconds to see your own mix before installing anything: [audit §2](audit/audit-commands.md) is one copy-paste command.

Cumulative: roughly **$1,100 less spend** than the old mix would have cost — $882 actual vs. a $1,978 counterfactual (497M tokens × the $3.98 baseline; order of magnitude, not an invoice). One user, subscription quota priced at API list rates, and quality is self-report: over 26 days of daily use I couldn't tell the difference from running everything on one model. The rest of the fine print — period pricing, cache multipliers, exactly what sits in the denominator — lives with the [audit commands](audit/audit-commands.md), where every number can be re-run against your own disk.

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
| Judgment (review / design / research) | [`judge`](agents/judge.md) | opus (pinned) | session |

Models are pinned in agent frontmatter — the settings block at the top of each agent file — so the table holds even when nobody is thinking about it. The second dimension matters more than it looks: `effort: low` alone cut scout's output tokens 41% with no perceived quality loss on recon work.

**Layer 2 — judgment-tier split, done by the orchestrator itself.** Light judgment (single-file review, copy review, two-way choices) gets `judge` with an explicit sonnet downgrade; heavy judgment (architecture, cross-file review, open-ended design) rides `judge`'s default opus; unsure stays untagged, which now safely means opus. This is the "dynamic routing" part of the system, and it needs no infrastructure at all — see below.

**Layer 3 — the mechanical gate** ([hooks/agent-model-guard.sh](hooks/agent-model-guard.sh)) — a PreToolUse hook, i.e. a script Claude Code runs before letting a tool call through. If Claude tries to hire a helper without naming a model, the hook **denies** the request and hands the routing table back in the rejection message; Claude re-sends it with a model attached. Rules prevent habit; the gate prevents mistakes.

Escalation rule that keeps the cheap tiers honest: if a cheap tier botches a task once, re-dispatch one tier up. Never retry at the same tier.

## Install

Four files, one settings entry, one policy block. From a clone of this repo (the hook needs `jq` — `command -v jq` to check):

```bash
mkdir -p ~/.claude/agents ~/.claude/hooks
cp agents/scout.md agents/worker.md agents/judge.md ~/.claude/agents/
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
- **Agent names resolve project-first.** If a project defines its own `scout`/`worker`/`judge`, that definition wins over `~/.claude/agents/`. Keep these names unique in your setup, and if you add your own pinned agents, extend the hook's allowlist (`scout|worker|judge|fork`) to match.
- **The hook validates the requested spawn, not the resolved model.** It closes the "forgot to tag" failure mode — which in my measurements was the entire leak — not every conceivable misconfiguration.

Smoke test: in any session, ask Claude to spawn a general-purpose subagent *without* specifying a model. Expected: the spawn is denied, the deny reason echoes the routing table, and Claude re-issues it with a model attached. Tested on Claude Code 2.1.210, Aug 2026. If it never denies: check `jq` is installed, the script path in settings.json resolves, and the matcher is exactly `Agent` — hook payload schemas can drift between versions, so diff against the changelog if you're far from 2.1.210. If it denies but Claude doesn't re-issue, that's model compliance, not the hook. Failure mode is open by design: a crashing hook surfaces an error and the spawn proceeds — worst case is stock behavior, not a bricked session.

That's the whole install. No daemon, no proxy, no npm.

## Day two: what actually changes

Nothing about how you talk to Claude. You ask for what you want; the policy block steers the delegation:

- *"Where is the retry logic defined?"* → Claude sends `scout` — Haiku, read-only — and gets file:line back.
- *"Apply that rename across the repo"* → `worker` — Sonnet, hands only, no design decisions.
- *"Review this diff properly"* → `judge` — opus pinned in frontmatter; light reviews get an explicit sonnet downgrade.

You can also route by hand whenever you feel like it: *"send scout to map the auth module first"*, *"have worker apply the spec"* — the agent names become shared vocabulary between you and Claude.

When the gate fires, it looks like this in the transcript — a bounced request, not an error:

> agent-model-guard: this Agent call has no model and would silently inherit the main-thread model. Re-issue it per the routing table: judgment → judge (opus pinned; tag sonnet for light judgment), mechanical execution → worker, read-only recon → scout. …

Claude reads that, re-issues with a model, and the work continues. Mostly you'll notice it *never* firing — that's the point.

Once a month (or after changing your setup), re-run [audit §2](audit/audit-commands.md) and check two numbers: the frontier model's share of subagent tokens (should be ~0 unless you asked for it by name) and whether the model mix is drifting where you expect.

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

## Update (2026-08-09): the last discipline-held tier got pinned

The judgment row above originally read "general-purpose + remember to tag opus" — the only tier held up by dispatch discipline (plus the hook) instead of a pinned definition. What exposed it: porting this policy to a second CLI (Codex Desktop, as three native custom-agent TOMLs). The port pinned every role in config — including the generic fallback — and the asymmetry became hard to unsee. So the fix flowed back: [`judge`](agents/judge.md) pins opus in frontmatter, light judgment becomes an explicit sonnet downgrade on the same agent, and the hook allowlist grew one name. Rule 2 of the method — pin beats discretion — now applies to all three rows.

## Update (2026-08-11): eight more days, 6.3× the volume

The obvious objection to a 26-day n=1 is that the window might just have been quiet. It wasn't quiet afterwards: over the next 8 days (Aug 4–11) subagent dispatch went from **87 to 545 assistant turns per day — 6.3× the volume** — and the routing held. Fable leaked **zero** times. The volume-held counterfactual for that window: $52.24 actual against $108.75 at the pre-routing mix (−52%), and $54.20 at the hardened mix — **3.6% apart**. That last number is the real finding: the system is done, what's left is coins.

One figure in that window is a trap, and it's worth showing rather than burying. Headline unit cost fell again — $1.31 → **$0.79 per M tokens** — and almost none of that is routing. Cache reads went from 84.2% to 91.5% of tokens, and cache reads bill at 0.1×, so the denominator inflated. Strip the cache and the routing-only figure moved the *other* way: $12.01 → $14.07 per M in+out tokens, because output's share of in+out went from 74.9% to 92.8% and output bills 5×. Same routing, different conversation shape. **Read both, always** — [§3](audit/audit-commands.md) is what you spent, [§2](audit/audit-commands.md) is what routing did.

The last thing this window changed is the framing. Subagents were 21% of in+out token flow but only **10% of spend** ($413 of $4,200 across those 8 days) — the gap between those two numbers *is* the routing working. The other 90% sits on the main thread, where a frontier model is a deliberate choice rather than an unaudited default. That's the honest ceiling: this repo makes delegated work cheap, and has nothing to say about what you pick for yourself.

## Known gaps

- **In-workflow `agent()` calls bypass the Agent hook** (PreToolUse never fires for them). Soft-constrained by the policy block only. Measured leakage: 7 calls ≈ $6 over 19 days — not worth a gate.
- **`fork` agents are exempt by design** — inheritance is their semantic; the model param is a no-op.
- **Re-measured 2026-08-11** (was: an open question about the opus tier's share): opus is **31.7% of subagent in+out tokens and 47.9% of subagent spend**, down from 35.1% / 54.2% in the hardened window. The light-judgment split is working, just slowly. For the record, the "~52%" this bullet used to quote was almost certainly a spend figure recorded as a token figure — hence both numbers, separately, from here on.
- **September re-test:** Sonnet's introductory pricing ($2/$10) ends **Aug 31, 2026** → $3/$15 ([confirmed on the pricing page](https://platform.claude.com/docs/en/about-claude/pricing); no extension). Recomputed against the Aug 4–11 window that's **+26% on subagent spend**, not the ~20% first estimated, putting unit cost near $0.99. List price, not routing regression.
- Model aliases (`opus`, `sonnet`, `haiku`) resolve forward: mid-run, the `opus` alias picked up a newer Opus at the same price — a free upgrade here, but pin exact model IDs if you need determinism.

## License

[MIT](LICENSE) · Questions and corrections: open an issue. I'm [@vinentW789](https://x.com/vinentW789) on X.
