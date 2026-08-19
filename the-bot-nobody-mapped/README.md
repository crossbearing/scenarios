# the bot nobody mapped

An AI release agent cuts a production release in a developer's Claude Code
session. Its transcript is honest about what *it* did: it cut a release branch
and opened a PR. But two more writes land on the production repo inside that
same window — a force-push of the built bundle and an auto-merge of the release
PR — and both were done by `deploy-shuttle[bot]`, a GitHub App. The org audit
log records the bot as the actor. No human is named, because **nobody maintains
the app → human installation mapping**. Two production changes, and the records
cannot tell you whose hands were on them.

The fix is that mapping: the login of the App bound to the human who installed
and owns it. With it, `deploy-shuttle[bot]` resolves to a named, record-proven
human instead of a blank — and, because the engine now stamps that human into
every event the mapped bot emits, the two production writes stop being
**unattributed** entirely. The mapping is a first-class report flag
(`--github-app-humans`), so the proof runs end-to-end from the CLI — see
[The fix](#the-fix) and [The proof](#the-proof).

## The story

`deploy-shuttle[bot]` is a GitHub App installed on the `shuttlecorp` org to
automate production deploys: when a release PR appears on `prod-web`, the App
builds the bundle, force-pushes it to the release branch, and merges the PR to
ship. In this session a Claude Code agent, run by release engineer
`mira-chen`, cuts the `2026.07.21` release. The audit log is the join of two
actors:

| What the agent claimed | What the org audit log recorded | Actor | Finding |
|---|---|---|---|
| `mcp:github:create_branch` (`release/2026.07.21`) | `git.create_ref` | `mira-chen` | **corroborated** |
| `Bash(gh pr create …)` (PR #482) | `pull_request.create` | `mira-chen` | **corroborated** |
| *(nothing)* | `git.push` to `prod-web` | `deploy-shuttle[bot]` | **unattributed** |
| *(nothing)* | `pull_request.merge` of #482 | `deploy-shuttle[bot]` | **unattributed** |

Read the transcript alone and the agent looks careful and complete: it cut the
branch, opened the PR, checked the merge state, and stopped. It never claimed to
*ship* anything — and it didn't. The two writes that actually changed
production, at 09:15:02 and 09:18:40, belong to the App the agent's PR woke up.

The human half of the log attributes cleanly: `mira-chen` is a GitHub username,
so the platform authenticated her and the actor **is** the named human
(`actor-identity`). The App half does not. A `[bot]` actor is an agent
fingerprint, not a person; it binds to a human only through an installation
mapping the operator supplies — and here there is none. So the App's two
production writes land in the strongest tier the engine has for "someone needs
to look at this": **unattributed**.

## The evidence

Two captured streams, both offline, both in the real schemas:

- [`claims/transcript.jsonl`](claims/transcript.jsonl) — the agent's Claude Code
  session on 2026-06-24: two writing tool calls (an MCP `create_branch`, a
  `gh pr create`) plus a read, with their results, a ~20-minute window.
- [`records/github-audit.json`](records/github-audit.json) — four GitHub org
  audit-log entries in that window. Two by `mira-chen` (the branch and the PR),
  two by `deploy-shuttle[bot]` (the push and the merge). The bot entries carry
  `programmatic_access_type: "GitHub App server-to-server token"` and **no field
  that names a human** — that is the whole problem, captured.

The join runs fully offline. GitHub-only captures still take the `--aws-cloudtrail`
offline switch, so [`records/aws-cloudtrail-empty.json`](records/aws-cloudtrail-empty.json)
is an empty CloudTrail horizon (`[]`): no AWS creds, no `--region`, no live call.

## The detection

```sh
./run.sh
```

```
crossbearing divergence report
  window   2026-06-24 08:30:30Z → 2026-06-24 09:50:05Z (offline (captured CloudTrail))
  session  prod-release-2026-06-24
           agent=claude-code human=UNATTRIBUTED (unattributed) active 2026-06-24 09:00:30Z → 2026-06-24 09:20:05Z
  claims   3 in transcript · 2 record-corroborable (aws CLI vocabulary)
  records  4 in window · 4 joined (agent principal ~ "mira-chen")

  unattributed 2 · mismatch 0 · unclaimed-record 0 · unrecorded-claim 0 · corroborated 2

ATTRIBUTION
  agent session prod-release-202… ≈ credential session github:mira-chen@2026-06-24T09:00:35Z
    window-overlap · human=mira-chen (actor-identity) · evidence: 2 item(s)
    gap: records name the human; the agent session declared no operator — pass --operator so the declaration can be cross-checked against the records

UNATTRIBUTED (2)
  record  github-audit:git.push on shuttlecorp/prod-web, shuttlecorp at 09:15:02Z by deploy-shuttle[bot]
          event gh-3
  why     production-touching action with agent fingerprints and no named human binding

  record  github-audit:pull_request.merge on shuttlecorp/prod-web, shuttlecorp at 09:18:40Z by deploy-shuttle[bot]
          event gh-4
  why     production-touching action with agent fingerprints and no named human binding
```

(Full pinned output, including the two CORROBORATED findings, in
[`expected-output.txt`](expected-output.txt).)

The **how-it-happens** is what the ATTRIBUTION block does *not* contain. It names
exactly one credential session — `github:mira-chen`, resolving to
`human=mira-chen (actor-identity)`. `deploy-shuttle[bot]` gets no binding line at
all, because a GitHub App actor carries no access key and no assumed-role session
name, so there is nothing for the engine to bind a session to. The App exists in
this report only as records. Same window, same production repo: the engine can
name one hand on the wheel, and for the other it has no line to write. The
**how-we-help** is the UNATTRIBUTED tier: the two production writes the log could
not assign to anyone are pulled out by name and event ID, not left in a scroll of
routine audit noise.

The `gap:` line under the `mira-chen` binding is the convention nudge, not a
finding: the records *do* name a human here (mira-chen, cloud-authenticated as
herself), yet the harness that launched the agent declared no operator, so there
is no operator string to cross-check those records against. Passing
`--operator mira-chen` would clear it — but it does nothing for the *bot*'s two
writes, which name no one on either side. (Do not reach for `--operator` as a fix
for the bot; see [the tempting hack](#the-tempting-hack-the-scenario-refuses) below.)

Why *unattributed* and not merely *unclaimed*? The engine escalates an unclaimed
in-window record to unattributed only when **no one is named anywhere**
([`internal/corroborate/matcher.go:116`](../../crossbearing/internal/corroborate/matcher.go)):
the record is **production-touching** (`--production-match prod-` matched the
`shuttlecorp/prod-web` target), the session it falls in names **no human**, *and*
the record itself carries **no per-event identity** (`Record.SourceIdentity == ""`
— the normalized slot for STS SourceIdentity, K8s impersonation, GCP/Azure
delegation). A `deploy-shuttle[bot]` audit entry carries none of those, and no
session names a human for it, so both bot writes escalate. Record-carried
identity would de-escalate on its own — but *without a mapping*, the bot's
records carry none.

### An honest detail: unattributed, but *not* agent-suspect

The exemplar scenario ends with an AGENT-SUSPECT tier — the unattributed records
positively fingerprinted to the agent's own proven credential. **This report has
no such section, and that is correct.** The agent-suspect classifier promotes a
record only on a *named positive signal*: a proven access key, or an operator-supplied
session-name pattern ([`internal/attribute/scope.go:59`, `:71`](../../crossbearing/internal/attribute/scope.go)).
A GitHub audit record carries neither — no access key, no assumed-role session
name. So the engine will not claim the App's push *is* the agent's. It isn't:
`deploy-shuttle[bot]` is a wholly separate actor the agent merely triggered. The
truthful posture is exactly what the report shows — a production change that is
unattributed and *not even the agent's*, which is precisely why "nobody mapped
it" is the whole finding.

## The fix

The gap is a missing entry in the App → human installation mapping. Whoever
installed `deploy-shuttle[bot]` on the org — here, platform lead
`dana-okafor@shuttlecorp.com` — is the human accountable for what it does. The
engine models this on `github.Options.AppHumans`
([`internal/ingest/github/ingest.go:39-43`](../../crossbearing/internal/ingest/github/ingest.go)),
and the report command accepts it from the CLI as `--github-app-humans <file>`,
a flat JSON object of `{"bot-login": "human"}`
([`cmd/crossbearing/main.go:104`](../../crossbearing/cmd/crossbearing/main.go)):

```diff
  {
-
+   "deploy-shuttle[bot]": "dana-okafor@shuttlecorp.com"
  }
```

([`fix/app-humans.before.json`](fix/app-humans.before.json) →
[`fix/app-humans.after.json`](fix/app-humans.after.json).) The flag is
fail-closed: a named file that cannot be read or parsed is an error, never a
silently empty mapping — a dropped mapping would report accountable actions as
unattributed
([`cmd/crossbearing/main.go:674-690`](../../crossbearing/cmd/crossbearing/main.go)).

Two things happen when the actor is a mapped bot. First, the ingester binds the
bot's record **session** to that human with method `github-app` — a record-proven
binding, because the installation is a fact in GitHub the agent cannot edit, not
a self-declared operator string
([`internal/ingest/github/ingest.go:247-250`](../../crossbearing/internal/ingest/github/ingest.go),
`AttrGitHubApp` at
[`internal/corroborate/types.go:64`](../../crossbearing/internal/corroborate/types.go)).
Second — and this is what closes the finding — the ingester stamps the mapped
human into **per-event `Record.SourceIdentity`** on every event that bot emits
([`internal/ingest/github/ingest.go:189-193`](../../crossbearing/internal/ingest/github/ingest.go)).
The actor login is on every entry and the mapping is deterministic, so this is
per-event identity — the GitHub analogue of STS SourceIdentity — and under the
hybrid escalation rule it short-circuits the escalation regardless of which
overlapping window claims the record.

That per-event stamp is what the earlier design note asked for, and the arc got
both halves it needed: the **flag** to hand the mapping to the CLI, and the
**per-event stamping** to make the outcome rest on the record rather than on
window overlap. Without the stamp, a mapped bot session would only *sometimes*
win — the bot writes fall inside two overlapping windows, the bot's own (now
named, if mapped) and the agent's claim session (unnamed, no `--operator`), and
the escalation evaluates the record against whichever window it lands in
([`sessionForRecord`, `matcher.go:163`](../../crossbearing/internal/corroborate/matcher.go)).
A session-only binding would leave the finding count resting on that coin-flip.
The per-event `SourceIdentity` removes the coin-flip: the App's owner travels
with each action the way a cloud source identity does, so the de-escalation is
deterministic. That is what turns `--github-app-humans` from "names the App in
one ATTRIBUTION line" into "closes the finding the way the trust-policy fix
closes the deploy scenario."

This is a *convention plus its per-event enforcement*, not a per-run flag you
tune. The mapping is data the operator owns — one line per installed App,
updated when ownership moves, the GitHub-side equivalent of the STS
SourceIdentity convention the CloudTrail scenarios enforce. The engine consumes
it and stamps it onto the records.

### The tempting hack the scenario refuses

There is a shortcut that looks like the fix and is not, and it is worth naming
so the reader does not reach for it. `--operator dana-okafor` also drops both
findings from UNATTRIBUTED to UNCLAIMED-RECORD — but for the wrong reason, and
with a lie attached. The escalation de-escalates as soon as the session a record
falls into names a human
([`matcher.go:116`](../../crossbearing/internal/corroborate/matcher.go)); the bot
writes fall inside the *agent's* claim-session window, so declaring the agent's
operator stamps `human=dana-okafor (declared)` on that window and the bot writes
inherit it. Self-declared, window-overlap-only — the weakest binding the engine
grades — now sits on the App's production push, an action `dana-okafor` never
took and the records never tied to them. That is masking, not mapping. The
mapping fix binds `github-app` from a fact in GitHub; the `--operator` hack binds
`declared` from a string the operator typed. Same de-escalation, opposite
truthfulness — which is exactly why the scenario ships the flag, not the hack.

## The proof

Re-run the same window with the operator's installation mapping supplied to the
CLI. `run-fixed.sh` is `run.sh` plus one flag —
`--github-app-humans fix/app-humans.after.json` — nothing else changes.

```sh
./run-fixed.sh
```

```
  unattributed 0 · mismatch 0 · unclaimed-record 2 · unrecorded-claim 0 · corroborated 2

ATTRIBUTION
  agent session prod-release-202… ≈ credential session github:mira-chen@2026-06-24T09:00:35Z
    window-overlap · human=mira-chen (actor-identity) · evidence: 2 item(s)
    gap: records name the human; the agent session declared no operator — pass --operator so the declaration can be cross-checked against the records

UNCLAIMED-RECORD (2)
  record  github-audit:git.push on shuttlecorp/prod-web, shuttlecorp at 09:15:02Z by deploy-shuttle[bot] as dana-okafor@shuttlecorp.com
          event gh-3
  why     infrastructure recorded this action inside an agent session window; no claim accounts for it

  record  github-audit:pull_request.merge on shuttlecorp/prod-web, shuttlecorp at 09:18:40Z by deploy-shuttle[bot] as dana-okafor@shuttlecorp.com
          event gh-4
  why     infrastructure recorded this action inside an agent session window; no claim accounts for it
```

(Full pinned output in [`expected-output-fixed.txt`](expected-output-fixed.txt);
every run is byte-for-byte identical.)

The headline moves the whole distance: `unattributed 2 → 0`. Notice where it does
*not* show up — the ATTRIBUTION block is byte-identical to the detection's. The
mapping conjures no credential session for the App; there is still no key and no
session name to bind one to. What it does is stamp the mapped human onto every
event the App emitted, so every bot record now renders that identity inline
(`… by deploy-shuttle[bot] as dana-okafor@shuttlecorp.com`) and the mapping is
legible at the exact line where the de-escalation happens. The App stops being
anonymous on the record — the only place it was ever visible.

And the two production writes? They are **still there** — `run-fixed.sh` still
lists them as `UNCLAIMED-RECORD`, because the agent still never claimed them, and
that is a real gap worth chasing. What changed is the class: they are no longer
**unattributed**. The push and the merge the records could not assign to anyone
now have an owner. `unattributed 2 → 0`, on the strength of the per-event stamp
alone — no `--operator`, no masking.

One honest detail remains in the fixed output, and the report names it. The
**`gap:` line still appears**, under the single `mira-chen` binding, unchanged
from the detection:

> gap: records name the human; the agent session declared no operator — pass
> --operator so the declaration can be cross-checked against the records

The records name mira-chen; the harness that launched the agent declared no
operator, so there is nothing to cross-check them *against*. Passing
`--operator mira-chen` clears it and lets the engine confirm the declaration
matches the record-proven identity (raising `CONFLICT` if it didn't) — and here
it costs nothing else: the two unclaimed records and two corroborations are
unchanged. The mapping fixes the *bot* half of this scenario and does nothing for
the human half, and the report keeps saying so. That is correct: mapping a bot to
its owner is a different remediation from declaring the agent's operator, and the
fixed run proves the first without pretending to have done the second.

That is the point of the whole gallery in one flag: the installation mapping did
not make the agent honest about what its PR triggered. It made the trigger
*accountable* — bound to a human you can go ask, stamped onto every event the App
emits. Detection told you exactly which line of the mapping to add; the proof is
the same window read back with a name on it.

## Files

| File | What it is |
|---|---|
| [`claims/transcript.jsonl`](claims/transcript.jsonl) | The agent's Claude Code session (claim stream) |
| [`records/github-audit.json`](records/github-audit.json) | GitHub org audit-log capture — two human entries, two unmapped App entries (the divergence) |
| [`records/aws-cloudtrail-empty.json`](records/aws-cloudtrail-empty.json) | Empty CloudTrail horizon (`[]`) — the offline switch for a GitHub-only capture |
| [`fix/app-humans.before.json`](fix/app-humans.before.json) · [`.after.json`](fix/app-humans.after.json) | The App → human mapping pair; the added line is the whole remediation |
| [`run.sh`](run.sh) · [`expected-output.txt`](expected-output.txt) | The detection and its pinned output |
| [`run-fixed.sh`](run-fixed.sh) · [`expected-output-fixed.txt`](expected-output-fixed.txt) | The proof — `run.sh` plus `--github-app-humans` — and its pinned output |

Both runs are deterministic: every invocation is byte-for-byte identical to its
pin.

## Note on the engine's semantics

Everything above is what the engine actually emits — both the detection and the
proof are pinned and deterministic. The claims summary reads "aws CLI vocabulary"
even though this stream is GitHub; that label is the engine's fixed wording for
the record-corroborable scope, not a claim about AWS. The UNATTRIBUTED "why" line
in the detection reads "production-touching action with agent fingerprints and no
named human binding" — the engine's constant string; here the fingerprint is the
session-window overlap, and the point is precisely that the record carries *no*
stronger fingerprint tying it to the agent. The UNCLAIMED-RECORD "why" line in
the proof reads "infrastructure recorded this action inside an agent session
window; no claim accounts for it" — the record is still unclaimed, only no longer
unattributed. The engine observations above — the `--github-app-humans` flag and
its fail-closed parse, the escalation rule that de-escalates on a named session
**or** a per-event `Record.SourceIdentity`, and the ingester stamping the mapped
human onto both the session and every event — were verified against the source
cited inline and against the engine built from `cmd/crossbearing`. The `gap:`
lines are the same hybrid-escalation convention nudge the CloudTrail scenarios
emit: records name a human, the harness declared no operator.
