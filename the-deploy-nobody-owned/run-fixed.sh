#!/usr/bin/env bash
# the deploy nobody owned — the proof.
#
# Same window, re-captured after the fix. The deploy role's trust policy now
# requires sts:SourceIdentity (fix/trust-policy.after.json), so every
# AssumeRole must name its human — priya@example.com rides on every CloudTrail
# event (userIdentity.sessionContext.sourceIdentity). That per-event,
# record-carried identity is what closes the headline: it de-escalates the
# production write on its own, whatever the launch side declared.
#
# The unclaimed lambda:UpdateFunctionCode is still unclaimed by the agent — a
# real gap the report keeps showing — but it is no longer ownerless: the
# record itself names priya via sts-source-identity, so the finding drops from
# UNATTRIBUTED to a plain UNCLAIMED-RECORD owned by a named human.
set -euo pipefail
cd "$(dirname "$0")"

# --operator declares the same human the records already carry, and it earns its
# place here rather than just clearing a convention nudge. The join will not let
# a claim consume a WRITE it cannot prove is the agent's — the guard keys on
# read-vs-write, not on production-ness — and ownership is proved by the record's
# sourceIdentity equalling the session's human. Drop this flag and the session
# has no human, so nothing matches: lambda:PublishVersion splits into an
# UNCLAIMED-RECORD plus an UNRECORDED-CLAIM (unclaimed-record 1 → 2,
# corroborated 3 → 2), and an ATTRIBUTION gap line appears asking for it. With
# it, declaration and record agree — the session line reads (declared), the
# ATTRIBUTION line binds (sts-source-identity), and the report raises neither a
# gap nor a CONFLICT.
"${CROSSBEARING:-crossbearing}" report \
  --transcript       claims/transcript.jsonl \
  --aws-cloudtrail   records/aws-cloudtrail-fixed.json \
  --production-match prod- \
  --operator         priya@example.com
