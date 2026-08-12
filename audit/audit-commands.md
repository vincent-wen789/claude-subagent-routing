# Audit commands — measure it yourself

Claude Code writes every session transcript to `~/.claude/projects/**/*.jsonl`. Subagent activity is marked `isSidechain: true`, with the model and token usage on each assistant turn. That's enough to verify, from your own disk, which models your subagents actually ran on and what they cost — no telemetry, no third-party tool.

The fine print — read this once before comparing numbers (the README's headline figures all carry these definitions):

- **Transcripts are cleaned up after ~30 days.** Baselines you don't snapshot in time are gone forever. Run the audit *before* you change anything, save the numbers, then re-run after.
- On a subscription plan these numbers are a **quota proxy priced at API list rates**, not an invoice. The ratios (model shares, before/after) are what matter.
- **Sonnet ran at its limited-time $2/$10** during the README's measurement window; list price returns to $3/$15 on Sep 1, 2026. §3 ships both prices — reproduce the README with the period prices.
- **Cache writes are billed at 2× the input price on the 1-hour TTL** (1.25× for 5-minute TTL). Before/after comparisons don't care — the same multiplier sits on both sides.
- **Unit cost (§3) = total spend over total tokens**, cache included on both sides of the fraction — so it also moves with conversation shape. **Model shares (§2) use in+out tokens only** — that's the routing-only signal. Read them together.
- **The README's counterfactual is volume-held**: it assumes the old mix would have burned the same 497M tokens; deny-and-reissue overhead and changed spawn habits aren't modeled. Its $882 actual is the summed spend of three windows whose volumes were uneven — it can't be backed out from the unit-cost rows alone.
- **Quality was not instrumented** — no escalation counts, no blinded comparison; the README's quality claim is self-report and labeled as such.

## 1. Token totals by model (all subagent turns on disk)

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 cat 2>/dev/null | \
jq -r 'select(.isSidechain == true and .message.usage != null) |
  [.message.model, .message.usage.input_tokens, .message.usage.output_tokens,
   (.message.usage.cache_creation_input_tokens // 0), (.message.usage.cache_read_input_tokens // 0)] | @tsv' 2>/dev/null | \
awk -F'\t' '{c[$1]++; i[$1]+=$2; o[$1]+=$3; w[$1]+=$4; r[$1]+=$5}
  END {printf "%-34s %7s %11s %11s %13s %14s\n","model","turns","input","output","cache_write","cache_read";
       for (m in c) printf "%-34s %7d %11d %11d %13d %14d\n", m, c[m], i[m], o[m], w[m], r[m]}'
```

A "turn" is one assistant message inside a subagent session. One spawn usually produces several turns, so turn counts are an upper bound on spawn counts — don't label them "calls".

## 2. Model share within a date window

Use this to bucket by period (before / after a routing change). Timestamps are ISO strings, so plain string comparison works:

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 cat 2>/dev/null | \
jq -r 'select(.isSidechain == true and .message.usage != null
              and .timestamp >= "2026-07-16" and .timestamp < "2026-08-04") |
  [.message.model, .message.usage.input_tokens, .message.usage.output_tokens] | @tsv' 2>/dev/null | \
awk -F'\t' '{c[$1]++; io[$1]+=$2+$3; t+=$2+$3}
  END {for (m in c) printf "%-34s %7d turns %12d tok %7.2f%%\n", m, c[m], io[m], 100*io[m]/t}' | sort -k4 -rn
```

Share here is on input+output tokens (cache excluded) — cache volume tracks conversation length more than work done, so it drowns the signal.

## 3. Cost at list prices

Edit the price table to current list prices (per M tokens; cache write shown at the 1-hour-TTL 2x multiplier, cache read at 0.1x — use 1.25x for 5-minute TTL; before/after comparisons are insensitive to the choice, since the same multiplier sits on both sides). To bucket by period, add a `.timestamp` range to the jq `select` exactly as in §2:

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 cat 2>/dev/null | \
jq -r 'select(.isSidechain == true and .message.usage != null) |
  [.message.model, .message.usage.input_tokens, .message.usage.output_tokens,
   (.message.usage.cache_creation_input_tokens // 0), (.message.usage.cache_read_input_tokens // 0)] | @tsv' 2>/dev/null | \
awk -F'\t' '
  BEGIN {
    pin["fable"]=10;  pout["fable"]=50
    pin["opus"]=5;    pout["opus"]=25
    pin["sonnet"]=3;  pout["sonnet"]=15   # list price from Sep 1, 2026.
    # The README figures for Jul-Aug 2026 used Sonnet limited-time pricing:
    # set pin["sonnet"]=2; pout["sonnet"]=10 to reproduce them.
    pin["haiku"]=1;   pout["haiku"]=5
    pin["unknown"]=0; pout["unknown"]=0
  }
  {
    tier="unknown"
    if ($1 ~ /fable/)       tier="fable"
    else if ($1 ~ /opus/)   tier="opus"
    else if ($1 ~ /sonnet/) tier="sonnet"
    else if ($1 ~ /haiku/)  tier="haiku"
    cost[tier] += ($2*pin[tier] + $4*pin[tier]*2 + $5*pin[tier]*0.1 + $3*pout[tier]) / 1e6
    tok[tier]  += $2 + $3 + $4 + $5
  }
  END {for (m in cost) {printf "%-8s $%9.2f %12d tok\n", m, cost[m], tok[m]; tot+=cost[m]; tt+=tok[m]}
       printf "%-8s $%9.2f %12d tok  ($%.2f per M tokens)\n", "TOTAL", tot, tt, tot*1e6/tt}'
```

The last figure — dollars per million tokens, with **all token types (input, output, cache write, cache read) in both the numerator and the denominator** — is the unit-cost number used in the README. Track it across windows; that's your before/after. An `unknown` row means a model the price table doesn't recognize slipped through at $0 — add its prices before trusting TOTAL. Cache volume tracks conversation length as well as model mix, so read this alongside the §2 model shares (computed on in+out only), which are the routing-only signal.

## 4. Leak detector — frontier-model spawns that shouldn't exist

If your policy says the frontier tier is by-name-only, this should return (almost) nothing:

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 grep -l '"isSidechain":true' 2>/dev/null | while read -r f; do
  n=$(jq -r 'select(.isSidechain == true and (.message.model // "" | test("fable"))) | .timestamp' "$f" 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && echo "$n leaked turns  $f"
done
```

Each hit gives you the session file — open it and check whether the spawn was named on purpose or slipped through a gap (in our case: `fork` agents and in-workflow `agent()` calls, which PreToolUse hooks don't see).

## 5. Subagent share of everything

Context for whether any of this matters for you — what fraction of your total in+out flow is subagents at all:

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 cat 2>/dev/null | \
jq -r 'select(.message.usage != null) |
  [(.isSidechain // false | tostring), .message.usage.input_tokens + .message.usage.output_tokens] | @tsv' 2>/dev/null | \
awk -F'\t' '{s[$1]+=$2; t+=$2} END {printf "subagent: %d (%.1f%%)  main thread: %d (%.1f%%)\n", s["true"], 100*s["true"]/t, s["false"], 100*s["false"]/t}'
```

Mine ran ~15% subagent in the hardened window. The bigger that number — and the more expensive your main thread — the more this repo is worth your ten minutes.

## 6. Is delegation itself paying off?

Everything above answers *which model your subagents run on*. It does not answer *whether spawning them beat doing the work inline* — a different question, and one that can go the other way.

The failure mode to watch for: you attach a cheap child to an expensive parent, the child does real work, and the parent **still** pays a similar synthesis bill because it re-reads the material and redoes the reasoning. Tokens get duplicated instead of moved, and the total goes up even though the child was cheap. A paired A/B on another CLI measured exactly this — a frontier root plus one cheap explorer child came out **8% more expensive** than the root working alone, with the child accounting for only 3.4% of spend and the root's own token count *rising*.

Settling that properly needs a paired A/B. But the specific failure mode is directly observable in transcripts you already have, no experiment required.

**6a. Compression ratio** — how much work the child absorbed versus how much it handed back:

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 cat 2>/dev/null | \
jq -r 'select(.timestamp >= "2026-08-04") |
  if (.isSidechain == true and .message.usage != null) then
    "SUB\t\(.message.usage.input_tokens + .message.usage.output_tokens)"
  elif (.message.content != null) then
    (.message.content[]? | select(.type=="tool_use" and (.name=="Agent" or .name=="Task")) | "ID\t\(.id)"),
    (.message.content[]? | select(.type=="tool_result") | "RET\t\(.tool_use_id)\t\([.content[]?.text // ""] | join("") | length)")
  else empty end' 2>/dev/null | \
awk -F'\t' '$1=="SUB"{s+=$2} $1=="ID"{id[$2]=1} $1=="RET"{ret[$2]=$3}
  END{for (k in ret) if (k in id) {n++; r+=ret[k]}
      printf "subagent work:      %12d in+out tok\n", s
      printf "returned to parent: %12d tok  (%d dispatches, avg %d)\n", r/4, n, r/4/n
      printf "compression ratio:  %12.0f : 1\n", s/(r/4)}'
```

Characters are converted to tokens at a flat ÷4 — rough, but the ratio is what matters. A high ratio means the child absorbed context the parent never had to hold. Mine: **85:1** (3.8M in+out tokens of child work, 45k tokens handed back across 118 dispatches).

**6b. Re-exploration rate** — the direct test for whether the parent redoes the child's work:

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 cat 2>/dev/null | \
jq -r 'select(.timestamp >= "2026-08-04") | select((.isSidechain // false) == false) | select(.message.content != null) |
  (.message.content[]? | select(.type=="tool_use")    | "USE\t\(.name)\t\(.id)"),
  (.message.content[]? | select(.type=="tool_result") | "RET\t\(.tool_use_id)\t-")' 2>/dev/null | \
awk -F'\t' '{l[NR]=$0} $1=="USE" && ($2=="Agent" || $2=="Task"){a[$3]=1}
  END{for (i=1; i<=NR; i++) {split(l[i],f,"\t")
        if (f[1]=="RET" && (f[2] in a)) {flag=1; continue}
        if (flag && f[1]=="USE") {nx[f[2]]++; tot++; flag=0}}
      print "First parent action after a subagent returns:"
      for (t in nx) printf "  %-18s %4d  %5.1f%%\n", t, nx[t], 100*nx[t]/tot
      redo = nx["Read"] + nx["Grep"] + nx["Glob"]
      printf "re-exploration (Read/Grep/Glob): %d of %d = %.1f%%\n", redo, tot, 100*redo/tot}'
```

If the parent's first move after a child returns is usually `Read`/`Grep`/`Glob`, it is going back to the source material — the duplication this section is about. If it is mostly writing, editing, or dispatching the next child, the parent is consuming conclusions. Mine: **2.9%** re-exploration; 63% of the time the next action was dispatching another child in the same parallel batch.

Neither number proves delegation is profitable — only a paired A/B does that. What they do is catch the specific way it goes wrong, cheaply, on data you already have.
