#!/usr/bin/env bash
# one key, two terminals — the proof.
#
# Same window, re-captured after the fix. The agent no longer wears the human's
# SSO cache: fix/launch-agent.sh assumes a dedicated agent-runner role with
# --source-identity dana@example.com, so the agent's calls carry a NEW access
# key (ASIAAGENTRUNR0001) and dana rides on every event as source identity. The
# human's manual PutBucketPolicy stays on their own SSO key (ASIASSOCACHE00001).
#
# Two keys, two identities. The manual write is now on a key the agent never
# touched, so it drops out of AGENT-SUSPECT entirely; the harness knows who
# launched the agent (--operator), so it also de-escalates out of UNATTRIBUTED
# to a plain UNCLAIMED-RECORD. The agent's own session binds to dana, cloud-
# proven via sts-source-identity.
set -euo pipefail
cd "$(dirname "$0")"

"${CROSSBEARING:-crossbearing}" report \
  --transcript       claims/transcript.jsonl \
  --aws-cloudtrail   records/aws-cloudtrail-fixed.json \
  --operator         dana@example.com \
  --production-match prod-
