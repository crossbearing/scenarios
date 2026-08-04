#!/usr/bin/env bash
# the bot nobody mapped — the detection.
#
# A Claude Code release agent cuts a production release of shuttlecorp/prod-web:
# its transcript claims a release branch (mcp github create_branch) and a
# release PR (gh pr create), then a status read. The GitHub org audit log
# corroborates those two — and records two more the agent never mentioned:
# deploy-shuttle[bot], a GitHub App, force-pushes the built bundle to the
# release branch and auto-merges the PR. Those are production-repo writes.
#
# The audit log's actor for a human username IS the named human (mira-chen
# binds to herself). A GitHub App actor is an agent fingerprint that binds to
# a human only through an installation mapping the operator supplies. Nobody
# maintains that mapping for deploy-shuttle[bot], so its two production writes
# name no human — the join surfaces them as UNATTRIBUTED.
#
# Offline and read-only: the transcript and audit-log capture are synthetic
# samples in the real schemas the engine validated against live. The empty
# aws-cloudtrail file is how a github-only capture runs offline (no --region,
# no AWS creds); the CloudTrail record horizon is simply empty here.
set -euo pipefail
cd "$(dirname "$0")"

# --principal names the identity the agent acts as: mira-chen ran this session,
# and an MCP/gh agent acts through her GitHub token, so the platform records her
# login as the actor. Asserting it is what lets her records corroborate the
# agent's claims. It is NOT a claim about the App — deploy-shuttle[bot] is a
# different actor, and its production writes stay unattributed, which is the
# finding this scenario exists to show.
"${CROSSBEARING:-crossbearing}" report \
  --transcript       claims/transcript.jsonl \
  --aws-cloudtrail   records/aws-cloudtrail-empty.json \
  --github-audit     records/github-audit.json \
  --github-org       shuttlecorp \
  --production-match prod- \
  --principal        mira-chen
