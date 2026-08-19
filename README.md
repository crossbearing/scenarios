# crossbearing scenarios

**Named divergences: what agents do wrong, how the records catch it, and the
fix that closes the gap.**

Every scenario in this gallery is a complete arc, runnable offline in
seconds, no cloud credentials:

1. **The story** — a misbehavior that actually happens when AI agents hold
   real credentials.
2. **The evidence** — captured audit records in the exact schemas the
   [crossbearing engine](https://crossbearing.dev) was live-validated
   against (CloudTrail, Kubernetes audit, GitHub org audit log). Identifiers
   are demo values; the shapes are real.
3. **The detection** — one command joins the agent's claims against the
   records and the finding surfaces.
4. **The fix** — the actual configuration change that closes the gap: a
   trust-policy diff, an enforced session convention, an identity mapping.
   Not "enable monitoring" — the specific lines.
5. **The proof** — the same command against post-fix records. Watch the
   finding change class.

Detection without remediation is a dashboard. The point of evidence is that
it tells you exactly what to change.

## Running a scenario

Each scenario runs against the crossbearing engine. The pinned outputs were
verified against the commit in [`.engine-pin`](.engine-pin), and CI replays every
scenario against **both** that commit and the engine's current `main` — so either
install reproduces what the READMEs show:

```sh
# the exact engine the pinned outputs were verified against
go install "github.com/crossbearing/crossbearing/cmd/crossbearing@$(cat .engine-pin)"

# or today's engine — CI proves the gallery still holds against it
go install github.com/crossbearing/crossbearing/cmd/crossbearing@latest

cd the-deploy-nobody-owned
./run.sh        # the detection — the finding as the records show it today
./run-fixed.sh  # the proof — the same window after the fix
```

Every run is offline and read-only: captured records in, a divergence report
out. `expected-output.txt` in each scenario pins what you should see.

## The gallery

| Scenario | The divergence | The fix |
| --- | --- | --- |
| [the-deploy-nobody-owned](the-deploy-nobody-owned/) | A production-touching action inside an agent's session window that the agent never claimed — and that no named human is accountable for | Enforce STS `SourceIdentity` in the deploy role's trust policy, so every credential names its human |
| [a-write-behind-a-read](a-write-behind-a-read/) | The agent claimed a read-only call; CloudTrail recorded a write at that moment on its credential | Least privilege: an explicit IAM Deny on the write actions the task never needed |
| [one-key-two-terminals](one-key-two-terminals/) | The human’s own manual production change, on the same cached SSO key the agent wields, pinned to the agent as agent-suspect | A dedicated agent-runner role assumed with `--source-identity` — separate keys for separate hands |
| [the-bot-nobody-mapped](the-bot-nobody-mapped/) | A GitHub App force-pushes and self-merges into a production repo; the audit log names no human behind the bot | The app→human installation mapping, handed to the engine via `--github-app-humans` — the mapped bot carries its human on every event |

More arcs are charted as record streams earn them. Each lands when its fix
walkthrough is as honest as its detection.

### Adding one

A scenario is a directory, and CI asserts the shape before it runs anything:
`README.md`, an executable `run.sh` and `run-fixed.sh`, and the
`expected-output.txt` / `expected-output-fixed.txt` pair they are pinned to.
A missing piece fails the run rather than being skipped.

Quote the report inside a **bare fenced block** and every line of it is checked
against the fixtures verbatim — that check is what keeps the prose and the tool
from drifting apart. Tagged blocks (`sh`, `json`, `diff`) are left alone.

## What this repo is not

The fixtures are synthetic and clearly labeled — no real account IDs, no
real principals. What is real: the record schemas, the join semantics, the
trust-policy mechanics, and the operational details (CloudTrail delivery
lag, session-key granularity, impersonation headers) that make the fixes
work in practice. Evidence produced by the engine stays verifiable without
it: see the MIT, zero-dependency
[verifier](https://github.com/crossbearing/verify).

## License

[MIT](LICENSE). Use the fixtures, the fixes, and the format however you
like.
