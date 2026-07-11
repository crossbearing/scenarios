#!/usr/bin/env bash
# one key, two terminals — the detection.
#
# A human runs a Claude Code agent under their cached SSO credentials. The SAME
# credentials — same access key — are live in the human's OTHER terminal, where
# they change a prod bucket's policy by hand. CloudTrail records both streams on
# one access key (ASIASSOCACHE00001), so the manual PutBucketPolicy lands inside
# the agent's session window on the credential the agent's own reads just proved
# is "the agent's". The SSO role carries no source identity, so nothing names a
# human. The join blames the agent: UNATTRIBUTED, and AGENT-SUSPECT.
#
# Offline and read-only: the transcript and CloudTrail capture are synthetic
# samples in the real schemas the engine validated against live. Identifiers are
# AWS-docs placeholders (111122223333, prod-checkout-artifacts, ASIA…0001).
set -euo pipefail
cd "$(dirname "$0")"

"${CROSSBEARING:-crossbearing}" report \
  --transcript       claims/transcript.jsonl \
  --aws-cloudtrail   records/aws-cloudtrail.json \
  --production-match prod-
