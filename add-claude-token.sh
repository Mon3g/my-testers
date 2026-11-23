#!/usr/bin/env bash
# Add the Claude token later (after a skipped setup.sh step 3, or to rotate it).
# The token is consumed only when a test run starts on GitHub runners — each
# tester is a Claude Code agent and needs a model to see the screen, decide taps,
# and write a report. It does NOT have to be an API key:
#   1) Claude Pro/Max subscription: run 'claude setup-token' and paste the token
#      (runs count against the plan, no separate bill)
#   2) Anthropic API key (pay per token)
# Usage: ./add-claude-token.sh   (run from the my-testers repo)
# KTW local addition, 2026-11-22 — upstream has no such script.
set -euo pipefail
command -v gh >/dev/null || { echo "Install the GitHub CLI first: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login"; exit 1; }
SECRETS=$(gh secret list --json name -q '.[].name' 2>/dev/null || true)
if grep -qxE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' <<<"$SECRETS"; then
  echo "A Claude token secret already exists — nothing to do (delete the secret first to replace it)."
  exit 0
fi
echo "Claude access — needed only when you RUN tests, not to install. Either:"
echo "  1) a Claude Pro/Max subscription: run 'claude setup-token' in another terminal and paste the token (no API key, counts against the plan)"
echo "  2) an Anthropic API key (pay per token)"
read -rp "Choose 1 or 2: " CHOICE
NAME=$([ "$CHOICE" = 2 ] && echo ANTHROPIC_API_KEY || echo CLAUDE_CODE_OAUTH_TOKEN)
read -rsp "Paste it (hidden): " VALUE; echo
if [ -z "$VALUE" ]; then echo "Empty — nothing set."; exit 1; fi
printf '%s' "$VALUE" | gh secret set "$NAME"
unset VALUE
echo "Secret $NAME set — test runs can now use the model."
