#!/usr/bin/env bash
# One-time setup of a testers repo (run it from the repo you created from this template):
#  1. creates the key pair that encrypts results (private half stays on this machine)
#  2. sets the ARTIFACT_PASSPHRASE secret
#  3. asks for your Claude token (subscription) or API key and stores it as a secret
#     — OPTIONAL at install time (choose 3 to skip); the token is only consumed
#     when a test run starts, never by the install itself. Add it later with
#     ./add-claude-token.sh before the first test run.
#  4. commits and pushes the public key
# LOCAL ADAPTATION (2026-11-22, KTW): step 3 made skippable — see note above the
# token block. Upstream setup.sh forces the token prompt at install time even
# though no test runs yet; this copy defers it.
set -euo pipefail
command -v gh >/dev/null || { echo "Install the GitHub CLI first: https://cli.github.com"; exit 1; }
command -v openssl >/dev/null || { echo "openssl is required"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login"; exit 1; }
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "Setting up agent testers for $REPO"
if [ "$(gh repo view --json visibility -q .visibility 2>/dev/null)" = PRIVATE ]; then
  echo "Note: $REPO is private. GitHub's runners are only free for public repos: here each macOS minute counts ten times against your Actions minutes."
fi

KEYDIR="$HOME/.mobile-agent-testers"; mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"
PRIV="$KEYDIR/${REPO//\//_}.pem"
if [ ! -f "$PRIV" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$PRIV" 2>/dev/null
  chmod 600 "$PRIV"
  echo "Private key created: $PRIV (keep it safe, never commit it)"
fi
openssl pkey -in "$PRIV" -pubout -out results_public.pem

SECRETS=$(gh secret list --json name -q '.[].name' 2>/dev/null || true)
if ! grep -qx ARTIFACT_PASSPHRASE <<<"$SECRETS"; then
  openssl rand -hex 32 | gh secret set ARTIFACT_PASSPHRASE
  echo "Secret ARTIFACT_PASSPHRASE set"
fi
# NOTE (local adaptation, 2026-11-22): the Claude token is NOT needed to install.
# It is only consumed when a test run starts on GitHub runners — each tester is
# a Claude Code agent, and without a model it cannot see the screen, decide taps,
# or write a report. So setup lets you skip this step and add the token later
# with ./add-claude-token.sh. It also does NOT have to be an API key: option 1
# uses a Claude Pro/Max subscription token (runs count against the plan, no
# separate bill).
if ! grep -qxE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' <<<"$SECRETS"; then
  echo
  echo "Claude access — needed only when you RUN tests, not to install. Either:"
  echo "  1) a Claude Pro/Max subscription: run 'claude setup-token' in another terminal and paste the token (no API key, counts against the plan)"
  echo "  2) an Anthropic API key (pay per token)"
  echo "  3) skip for now — install finishes without it; add it later with ./add-claude-token.sh"
  CHOICE=""
  while [ "$CHOICE" != 1 ] && [ "$CHOICE" != 2 ] && [ "$CHOICE" != 3 ]; do read -rp "Choose 1, 2 or 3: " CHOICE; done
  if [ "$CHOICE" = 3 ]; then
    echo "Skipped — run ./add-claude-token.sh before your first test run."
  else
    if [ "$CHOICE" = 1 ]; then
      NAME=CLAUDE_CODE_OAUTH_TOKEN PREFIX=sk-ant-oat KIND="token from claude setup-token"
      command -v claude >/dev/null || echo "Claude Code is not installed here: npm install -g @anthropic-ai/claude-code, then claude setup-token"
    else
      NAME=ANTHROPIC_API_KEY PREFIX=sk-ant-api KIND="Anthropic API key"
    fi
    while :; do
      read -rsp "Paste it (hidden): " VALUE; echo
      VALUE=$(printf '%s' "$VALUE" | tr -d '[:space:]')
      if [ -z "$VALUE" ]; then echo "Nothing pasted, try again."; continue; fi
      case "$VALUE" in "$PREFIX"*) ;; *) echo "Warning: it does not start with $PREFIX, like a $KIND does." ;; esac
      if [ "$CHOICE" = 2 ] && command -v curl >/dev/null; then
        # free endpoint, no tokens used; the key goes through stdin, not the command line
        STATUS=$(printf 'x-api-key: %s\nanthropic-version: 2023-06-01\n' "$VALUE" |
          curl -s -m 15 -o /dev/null -w '%{http_code}' -H @- https://api.anthropic.com/v1/models || true)
        if [ "$STATUS" = 401 ] || [ "$STATUS" = 403 ]; then echo "Anthropic refused this key ($STATUS): paste another one."; continue; fi
        [ "$STATUS" = 200 ] && echo "Key checked with Anthropic."
      fi
      break
    done
    printf '%s' "$VALUE" | gh secret set "$NAME"
    unset VALUE
    echo "Secret $NAME set"
  fi
fi

if ! git diff --quiet -- results_public.pem 2>/dev/null || ! git ls-files --error-unmatch results_public.pem >/dev/null 2>&1; then
  git add results_public.pem && git commit -qm "Add results public key" && git push -q
  echo "Public key committed and pushed"
fi
cat <<MSG

Done. Run the demo (2 Android + 2 iOS testers on the demo app, about 20 min):
  gh workflow run agent-testers.yml
Follow it:
  gh run watch
Then download and decrypt the reports:
  bash scripts/collect.sh \$(gh run list --workflow agent-testers.yml -L 1 --json databaseId -q '.[0].databaseId')
MSG
