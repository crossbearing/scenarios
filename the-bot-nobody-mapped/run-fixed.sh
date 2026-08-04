#!/usr/bin/env bash
# the bot nobody mapped — the fix.
#
# Same production release as run.sh: a Claude Code release agent claims a
# release branch and PR, and the GitHub org audit log records two more writes
# the agent never mentioned — deploy-shuttle[bot], a GitHub App, force-pushes
# the built bundle and auto-merges the PR. In run.sh those two surface as
# UNATTRIBUTED because no installation mapping names a human behind the bot.
#
# The fix hands the operator's installation mapping to the CLI:
# --github-app-humans fix/app-humans.after.json is the flat {bot: human}
# object the report flag parses ({"deploy-shuttle[bot]": "dana-okafor@…"}).
# A mapped bot stamps its human into per-event Record.SourceIdentity — the
# GitHub analogue of an STS SourceIdentity — so under the hybrid escalation
# rule its production writes de-escalate from UNATTRIBUTED to
# UNCLAIMED-RECORD, accountable "as dana-okafor", session bound via github-app.
#
# fix/app-humans.before.json is the empty mapping ({}) run.sh runs under
# implicitly — the before/after pair that isolates exactly what the mapping
# changes.
#
# Offline and read-only: same synthetic captures in the engine's real schemas.
set -euo pipefail
cd "$(dirname "$0")"

"${CROSSBEARING:-crossbearing}" report \
  --transcript        claims/transcript.jsonl \
  --aws-cloudtrail    records/aws-cloudtrail-empty.json \
  --github-audit      records/github-audit.json \
  --github-org        shuttlecorp \
  --production-match  prod- \
  --principal         mira-chen \
  --github-app-humans fix/app-humans.after.json
