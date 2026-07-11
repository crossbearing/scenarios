#!/usr/bin/env bash
# the deploy nobody owned — the detection.
#
# An AI deploy agent's transcript claims a caller-identity check, a
# get-function read, and a version publish against prod-checkout-api.
# CloudTrail recorded all three — and one more the agent never mentioned:
# a lambda:UpdateFunctionCode that pushed new code to a production function.
# The deploy role's trust policy does not require sts:SourceIdentity, so
# every credential on it is anonymous: that production write binds to no
# named human. The join surfaces it as UNATTRIBUTED.
#
# Offline and read-only: the transcript and CloudTrail capture are synthetic
# samples in the real schemas the engine validated against live. Identifiers
# are AWS-docs placeholders (111122223333, prod-checkout-api, ASIA…0001).
set -euo pipefail
cd "$(dirname "$0")"

"${CROSSBEARING:-crossbearing}" report \
  --transcript       claims/transcript.jsonl \
  --aws-cloudtrail   records/aws-cloudtrail.json \
  --production-match prod-
