#!/bin/bash
# agent-model-guard: spawning a subagent without an explicit model silently
# inherits the main-thread model. If your main thread runs a frontier model
# (Fable 5 = $10/$50 per M tokens, 2x Opus), every unrouted spawn bills at
# frontier rates.
#
# This PreToolUse hook denies any Agent call that neither uses a pinned-model
# agent nor passes an explicit `model` param, and bounces it back with the
# routing table. The orchestrator re-issues the spawn with a model attached.
#
# Allowlist:
#   scout/worker - models pinned in their agent definitions (see agents/)
#   fork         - inheritance is the semantic; the model param is a no-op
#
# (The original ran with this deny message in Chinese. Claude complied either way.)
input=$(cat)
st=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // "general-purpose"')
model=$(printf '%s' "$input" | jq -r '.tool_input.model // empty')
case "$st" in
  scout|worker|fork) exit 0 ;;
esac
if [ -z "$model" ]; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"agent-model-guard: this Agent call has no model and would silently inherit the main-thread model. Re-issue it with an explicit model per the routing table: judgment -> opus, light judgment -> sonnet, read-only recon -> haiku. Inheriting the main-thread model on purpose requires explicit user approval."}}'
  exit 0
fi
exit 0
