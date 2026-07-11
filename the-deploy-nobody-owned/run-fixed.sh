#!/usr/bin/env bash
# the deploy nobody owned — the proof.
#
# Same window, re-captured after the fix. The deploy role's trust policy now
# requires sts:SourceIdentity (fix/trust-policy.after.json), so every
# AssumeRole must name its human — priya@example.com rides on every CloudTrail
# event (userIdentity.sessionContext.sourceIdentity). That per-event,
# record-carried identity is all the proof needs: nothing is passed on the
# command line here.
#
# The unclaimed lambda:UpdateFunctionCode is still unclaimed by the agent — a
# real gap the report keeps showing — but it is no longer ownerless: the
# record itself names priya via sts-source-identity, so the finding drops from
# UNATTRIBUTED to a plain UNCLAIMED-RECORD owned by a named human. The report
# still asks the launch side to declare its operator, but as an ATTRIBUTION
# gap ("records name the human; the agent session declared no operator") — a
# convention todo, not a condition of the proof.
set -euo pipefail
cd "$(dirname "$0")"

"${CROSSBEARING:-crossbearing}" report \
  --transcript       claims/transcript.jsonl \
  --aws-cloudtrail   records/aws-cloudtrail-fixed.json \
  --production-match prod-
