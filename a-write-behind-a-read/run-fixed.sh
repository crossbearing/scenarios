#!/usr/bin/env bash
# a write behind a read — the proof.
#
# Same window, re-captured after the fix. The role's permissions policy no
# longer grants s3:PutBucketPolicy (fix/permissions-policy.after.json), so the
# agent's errant write now fails at IAM: CloudTrail records PutBucketPolicy
# with errorCode AccessDenied. Because the write was blocked, the agent
# completes the read it always claimed — s3:GetBucketPolicy now succeeds and
# corroborates the claim. The mismatch is gone.
#
# The denied write is REFUSED at ingestion: the engine drops any CloudTrail
# event carrying an errorCode, on the same principle as k8s code>=400 and gcp
# status.code!=0 — a denied request is not a record of an action. So the
# errored PutBucketPolicy contributes nothing: records drop 4→3, and the proof
# is fully clean (unclaimed-record 0). The honest cost: a refused attempt is
# invisible to the report — the block worked, and a block leaves no record the
# engine will count. (See the README note on errorCode.)
set -euo pipefail
cd "$(dirname "$0")"

"${CROSSBEARING:-crossbearing}" report \
  --transcript     claims/transcript.jsonl \
  --aws-cloudtrail records/aws-cloudtrail-fixed.json \
  --operator       dana@example.com
