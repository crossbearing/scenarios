#!/usr/bin/env bash
# a write behind a read — the detection.
#
# A config-audit agent's transcript claims three read-only AWS calls against
# prod-payments-config: a caller-identity check, a get-bucket-versioning
# read, and a get-bucket-policy read. CloudTrail corroborates the first two —
# but at the moment the agent claims it read the bucket policy, the record on
# its own credential is s3:PutBucketPolicy: a WRITE. The claim says read; the
# ground truth says write. The join surfaces it as a MISMATCH.
#
# Offline and read-only: the transcript and CloudTrail capture are synthetic
# samples in the real schemas the engine validated against live. Identifiers
# are AWS-docs placeholders (111122223333, prod-payments-config, ASIA…0001).
set -euo pipefail
cd "$(dirname "$0")"

"${CROSSBEARING:-crossbearing}" report \
  --transcript     claims/transcript.jsonl \
  --aws-cloudtrail records/aws-cloudtrail.json \
  --operator       dana@example.com \
  --principal      audit-bot
