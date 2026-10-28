#!/bin/bash
# agent-model-guard: spawning a subagent without an explicit model silently
# inherits the main-thread model. If your main thread runs a frontier model
# (Fable = $10/$50 per M tokens), every unrouted spawn bills at frontier rates.
#
# This PreToolUse hook denies any Agent call that neither uses a pinned-model
# agent nor passes an explicit `model` param, and bounces it back with the
# v2 routing rules. The orchestrator first checks whether the job should be
# delegated at all (v2 default: the main thread does it), then either does it
# inline or re-issues the spawn with a model attached.
#
# Allowlist:
#   worker/judge       - models pinned in their agent definitions (see agents/)
#   scout              - archived in v2 (agents/archive/), still allowlisted so
#                        v1 installs keep working
#   fork               - inheritance is the semantic; the model param is a no-op
#
# (The original ran with this deny message in Chinese. Claude complied either way.)
input=$(cat)
st=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // "general-purpose"')
model=$(printf '%s' "$input" | jq -r '.tool_input.model // empty')
case "$st" in
  scout|worker|judge|fork) exit 0 ;;
esac
if [ -z "$model" ]; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"agent-model-guard: this Agent call has no model and would silently inherit the main-thread model. First check whether it should be delegated at all (default: the main thread does it). If it should, re-issue per the routing table: independent perspective -> judge (opus pinned; tag sonnet for cold reads), large-batch mechanical work -> worker, recon -> Explore with model haiku. Inheriting the main-thread model on purpose requires explicit user approval."}}'
  exit 0
fi
exit 0
