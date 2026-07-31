# one key, two terminals

A human runs a Claude Code agent under their own SSO login. The exact same
cached credentials — the same access key — are live in a second terminal the
human keeps open, and in that terminal they change a production bucket's policy
by hand. CloudTrail records both streams on **one access key**, so the manual
change lands inside the agent's session window on the credential the agent's own
reads just proved is "the agent's." The engine, reading the evidence it actually
has, pins the human's action as the agent's: **unattributed**, **agent-suspect**.

Nobody is really accountable. The agent is blamed for a change it never made; the
human's hand on production is hidden behind a robot's name. This is the
credential-hygiene trap — and unlike the other arcs in this gallery, the agent
did nothing wrong. The records are telling the truth about the key; the key is
just shared. The fix is not a smarter join. It is a second identity.

## The story

`dana@example.com` signs in through IAM Identity Center and, in one terminal,
launches a Claude Code agent to audit `prod-checkout-artifacts`. The agent wears
Dana's cached SSO credentials because that is simply what is in the environment.
It narrates a careful, read-only pass:

| What the agent claimed | What CloudTrail recorded | Finding |
|---|---|---|
| `aws sts get-caller-identity` | `sts:GetCallerIdentity` | **corroborated** |
| `aws s3api get-bucket-policy --bucket prod-checkout-artifacts` | `s3:GetBucketPolicy` | **corroborated** |
| `aws s3api get-bucket-versioning --bucket prod-checkout-artifacts` | `s3:GetBucketVersioning` | **corroborated** |
| *(nothing)* | `s3:PutBucketPolicy` on `prod-checkout-artifacts` | **unattributed** → **agent-suspect** |

Every read the agent claimed corroborates a record. But at 14:11:30, halfway
through the agent's window, a `s3:PutBucketPolicy` rewrites the production
bucket's policy — a **write**, and it appears nowhere in the agent's account of
itself. Dana typed it, by hand, in the *other* terminal. CloudTrail cannot see
two terminals; it sees one assumed-role session on one access key
(`ASIASSOCACHE00001`), and the agent's three corroborated reads already proved
that key is the agent's. So the orphaned production write is fingerprinted to the
agent and, because the SSO role names no human, escalated to the strongest tier
the engine has: **unattributed**.

The cruel detail is in the principal itself. The role session name reads
`…/dana@example.com` — Dana's name is *right there* on every event. And the
engine still reports `human=UNATTRIBUTED`, because a role session name is a label
anyone in the SSO cache wears, the agent included. It is not a binding. That is
the whole trap in one line: the name looks like accountability and isn't.

## The evidence

Two captured streams, both offline, both in the real schemas:

- [`claims/transcript.jsonl`](claims/transcript.jsonl) — the agent's Claude Code
  session: three `Bash(aws …)` read-only tool calls with their results, a
  ~22-minute window on 2026-06-24.
- [`records/aws-cloudtrail.json`](records/aws-cloudtrail.json) — four CloudTrail
  management events, **all four on the same access key `ASIASSOCACHE00001`**.
  Three are the agent's reads; `ct-3` is Dana's manual `PutBucketPolicy`. No
  `sourceIdentity` anywhere — the SSO role doesn't set one — and no access-key
  boundary between the two humans-at-keyboards, because the SSO cache handed the
  same key to both terminals. That shared key is the whole problem, captured.

## The detection

```sh
./run.sh
```

```
  unattributed 1 · mismatch 0 · unclaimed-record 0 · unrecorded-claim 0 · corroborated 3

ATTRIBUTION
  agent session agent-audit-2026… ⇄ credential session dana@example.com@2026-06-24T14:00:09Z key=ASIASSOCACHE00001
    corroborated · human=UNATTRIBUTED (unattributed) · evidence: 3 item(s)

UNATTRIBUTED (1)
  record  s3:PutBucketPolicy on arn:aws:s3:::prod-checkout-artifacts at 14:11:30Z by arn:aws:sts::111122223333:assumed-role/AWSReservedSSO_Engineer_a1b2c3d4/dana@exa…
          event ct-3
  why     production-touching action with agent fingerprints and no named human binding

AGENT-SUSPECT (1 of 1 unattributed)
  record       s3:PutBucketPolicy by arn:aws:sts::111122223333:assumed-role/AWSReservedSSO_Engineer_a1b2c3d… (event ct-3)
  fingerprint  credential session proven to be the agent's by corroborated record ct-1
```

The **how-it-happens** is the ATTRIBUTION line: the credential session is
*proven* to be the agent's (three corroborated reads on key `ASIASSOCACHE00001`),
yet it binds to `human=UNATTRIBUTED` — Dana's name is in the principal but the
role establishes no identity the engine will trust. The **how-we-help** is the
AGENT-SUSPECT tier: the orphaned production write is pinned to that same proven
key. Which is *correct given the evidence* — and *wrong about the world*. Dana
did it, not the agent, and no record on this account can tell you that, because
the access key — the engine's sharpest instrument for separating "the agent's
session" from "someone else on the same role" — cannot separate two terminals
that share one SSO cache. That boundary is documented in the engine itself
([`internal/attribute/bind.go`](https://github.com/crossbearing/crossbearing):
"SSO credential caches hand the same role and session name to every terminal";
the access key separates credential *sessions*, but a single cache is a single
key).

Why *unattributed* and not merely *unclaimed*? The escalation needs all three:
the record is **production-touching** (`--production-match prod-` matched the
bucket ARN), it carries an **agent fingerprint** (the proven credential session),
and **no one is named anywhere** — the claim session declared no human *and* the
record carries no per-event identity. Remove any one and it de-escalates. Here
the manual write carries no `sourceIdentity` (Dana's interactive SSO key stamps
none) and the detection run declares no operator, so nothing names a human on
either side — it escalates. The fix removes two of the three at once, by removing
the shared key.

## The fix

Source identity on the SSO role would *not* fix this. Add it and both terminals,
sharing one cache, would carry the same `sourceIdentity: dana` — the manual write
would still land on the agent's proven key and stay **agent-suspect**. Naming the
human doesn't separate the hands. Separating the credentials does.

So the agent gets its **own** identity: a dedicated `agent-runner` role, assumed
with `--source-identity` naming the operating human, launched instead of handing
the agent Dana's SSO cache.

[`fix/launch-agent.sh`](fix/launch-agent.sh):

```sh
creds="$(aws sts assume-role \
  --role-arn          arn:aws:iam::111122223333:role/agent-runner \
  --role-session-name claude-agent \
  --source-identity   "$OPERATOR" \
  --query Credentials --output json)"

export AWS_ACCESS_KEY_ID=…      # from $creds — a NEW key: ASIAAGENTRUNR0001
export AWS_SECRET_ACCESS_KEY=…
export AWS_SESSION_TOKEN=…
exec claude "$@"
```

[`fix/agent-runner-trust-policy.json`](fix/agent-runner-trust-policy.json) is
what makes it enforceable — only Dana's SSO role may assume `agent-runner`, and
only while setting a source identity:

```json
{
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::111122223333:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Engineer_a1b2c3d4" },
  "Action":   [ "sts:AssumeRole", "sts:SetSourceIdentity" ],
  "Condition": { "StringLike": { "sts:SourceIdentity": "*@example.com" } }
}
```

Two things fall out of this, and both matter:

- **A different access key.** The agent now calls AWS on `ASIAAGENTRUNR0001`,
  never `ASIASSOCACHE00001`. The human keeps using their own SSO cache in their
  own shell. Nothing they do by hand can ever land on the agent's key again —
  the access key becomes the clean separator it was always meant to be.
- **`sts:SourceIdentity: dana@example.com` on every agent event.** Set once at
  assume time, immutable for the session, surviving role chaining, reappearing at
  `userIdentity.sessionContext.sourceIdentity` — the strongest cloud-side
  binding. The `StringLike` condition is the *requiring* form the engine's
  trust-policy parser reads as `RequiresSourceIdentity`
  ([`internal/attribute/conventions.go`](https://github.com/crossbearing/crossbearing));
  `sts:SetSourceIdentity` in the Action list is what permits the caller to set it
  at all. Tighten `"*@example.com"` to your identity domain to enforce the shape.

Source identity gives the agent's session a *name*; the separate role gives it a
separate *key*. The trap needed both undone.

## The proof

Re-capture the same window after the fix
([`records/aws-cloudtrail-fixed.json`](records/aws-cloudtrail-fixed.json)): the
agent's three reads now carry the `agent-runner/claude-agent` principal, key
`ASIAAGENTRUNR0001`, and `sourceIdentity: dana@example.com`; Dana's manual
`PutBucketPolicy` stays on the SSO principal and key `ASIASSOCACHE00001`. The
harness that launched the agent knows who is driving, so it declares it
(`--operator dana@example.com`).

```sh
./run-fixed.sh
```

```
  unattributed 0 · mismatch 0 · unclaimed-record 1 · unrecorded-claim 0 · corroborated 3

ATTRIBUTION
  agent session agent-audit-2026… ⇄ credential session claude-agent@2026-06-24T14:00:09Z key=ASIAAGENTRUNR0001
    corroborated · human=dana@example.com (sts-source-identity) · evidence: 6 item(s)
  agent session agent-audit-2026… ≈ credential session dana@example.com@2026-06-24T14:11:30Z key=ASIASSOCACHE00001
    window-overlap · human=dana@example.com (declared) · evidence: 0 item(s)

UNCLAIMED-RECORD (1)
  record  s3:PutBucketPolicy on arn:aws:s3:::prod-checkout-artifacts at 14:11:30Z by arn:aws:sts::111122223333:assumed-role/AWSReservedSSO_Engineer_a1b2c3d4/dana@exa…
          event ct-3
  why     infrastructure recorded this action inside an agent session window; no claim accounts for it
```

Read the two ATTRIBUTION lines together — this is the whole fix, rendered. There
are now **two** credential sessions where before there was one. The first (`⇄`,
corroborated) is the agent on its own key `ASIAAGENTRUNR0001`, bound to
`dana@example.com` by `sts-source-identity` — cloud-proven, not self-declared.
The second (`≈`, window-overlap) is Dana's *own* SSO terminal on
`ASIASSOCACHE00001`, now visibly distinct, bound to Dana by declaration because
it merely shares the wall clock. The two hands are finally on two keys.

And the production write? It is **still there** as an `UNCLAIMED-RECORD` — the
agent still never claimed it, and that remains true, because the agent never did
it. What changed is what the engine is willing to say about it. It is no longer
**agent-suspect**: it sits on `ASIASSOCACHE00001`, a key no corroborated finding
ties to the agent, so the fingerprint that promoted it is gone. And it is no
longer **unattributed**: it de-escalates to a plain unclaimed record owned by a
named human. `unattributed 1 → 0`; the AGENT-SUSPECT tier empties entirely.

That is the point of the arc: the fix did not teach the join to read minds. It
gave the agent a key of its own, so the records the engine already trusts stopped
conflating two people. Detection told you exactly what was shared; the proof is
the same window read back with the sharing undone.

## Files

| File | What it is |
|---|---|
| [`claims/transcript.jsonl`](claims/transcript.jsonl) | The agent's Claude Code session — three read-only claims (claim stream) |
| [`records/aws-cloudtrail.json`](records/aws-cloudtrail.json) | CloudTrail capture, all four events on one shared SSO key (the divergence) |
| [`records/aws-cloudtrail-fixed.json`](records/aws-cloudtrail-fixed.json) | Same window, agent on its own key + source identity, human on the SSO key (the fix) |
| [`fix/launch-agent.sh`](fix/launch-agent.sh) · [`fix/agent-runner-trust-policy.json`](fix/agent-runner-trust-policy.json) | Assume the dedicated agent role with `--source-identity`; the trust policy that enforces it — the whole remediation |
| [`run.sh`](run.sh) · [`run-fixed.sh`](run-fixed.sh) | The detection and the proof |
| [`expected-output.txt`](expected-output.txt) · [`expected-output-fixed.txt`](expected-output-fixed.txt) | Pinned outputs — every run is byte-for-byte identical |

## Note on the engine's semantics

Everything above is what the engine actually emits — the outputs are pinned and
deterministic. Four honest details, in the spirit of showing the seams:

- **Why `--operator` still earns its place here.** The escalation rule is: a
  production-touching record escalates to `unattributed` only when **no one is
  named anywhere** — the claim session declared no human **and** the record
  carries no per-event identity. Record-carried identity de-escalates on its own,
  regardless of the harness. But the record that matters in this scenario — Dana's
  manual `PutBucketPolicy` — sits on the interactive SSO key, which stamps **no**
  `sourceIdentity`. So that record carries no identity of its own; the only thing
  that names a human for it is the harness declaring its operator. That is why
  `run-fixed.sh` keeps `--operator dana@example.com`: drop it and the manual write
  re-escalates to `unattributed 1`. (The agent's *own* events do carry
  `sourceIdentity` now — they render `… claude-agent as dana@example.com` — but
  those reads were never the finding at risk.) The sibling deploy scenario is the
  mirror image: there the ownerless write *does* carry record-side identity, so
  the trust-policy fix closes it with no `--operator` at all.

- **The distinctive half is the key, not the name.** De-escalating out of
  **agent-suspect** does not depend on either of those — it depends only on the
  access key. AgentSuspect promotes a record solely when its `accessKeyId` is one
  a corroborated finding tied to the agent
  ([`internal/attribute/scope.go`](https://github.com/crossbearing/crossbearing)).
  Give the agent a separate key and the human's write is no longer on a proven
  key, full stop — which is why source identity on the *shared* SSO role would
  have left it agent-suspect, and why the real fix is a second identity.

- **The role session name is not a binding.** The SSO principal literally reads
  `…/dana@example.com`, yet the detection run reports `human=UNATTRIBUTED`. The
  engine never reads a role session name as a human identity — an SSO cache hands
  the same session name to every terminal, agent included, so it proves nothing.
  Only the attribution ladder (SourceIdentity, session tags, declared operator)
  sets `Human`. This is the package's founding lesson, not a gap.

- **The trust-policy check is live.** `RequiresSourceIdentity` is verified by an
  `iam:GetRole` read the offline runs skip; the `StringLike sts:SourceIdentity`
  requiring semantics quoted above were read from
  `internal/attribute/conventions.go`. Offline, the `UNATTRIBUTED` finding still
  lands from the join alone, carrying its own explanation.
