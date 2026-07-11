#!/usr/bin/env bash
# Launch a Claude Code agent under its OWN identity — never the human's cached
# SSO credentials. This is the whole remediation for "one key, two terminals":
# the agent stops sharing the human's access key, so CloudTrail can finally tell
# the two apart, and every agent action carries the operating human by name.
set -euo pipefail

# The human running the agent. In a real harness this is the signed-in SSO user,
# resolved from `aws sts get-caller-identity` or the SSO session — not typed by
# hand. It becomes the immutable sts:SourceIdentity on every call the agent makes.
: "${OPERATOR:?set OPERATOR to the human running this agent, e.g. dana@example.com}"

# The human is signed in via IAM Identity Center (their own cached credentials
# in ~/.aws/sso/cache). Instead of handing those straight to the agent — which
# is exactly the shared-key trap — assume a dedicated agent-runner role and
# stamp the operator into sts:SourceIdentity. Source identity is set once at
# assume time, is immutable for the life of the session, survives role chaining,
# and reappears on every event at userIdentity.sessionContext.sourceIdentity.
creds="$(aws sts assume-role \
  --role-arn          arn:aws:iam::111122223333:role/agent-runner \
  --role-session-name claude-agent \
  --source-identity   "$OPERATOR" \
  --query             Credentials \
  --output            json)"

AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId     <<<"$creds")"
AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<<"$creds")"
AWS_SESSION_TOKEN="$(jq -r .SessionToken    <<<"$creds")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# The agent now runs on a DIFFERENT access key (ASIAAGENTRUNR…) than the human's
# SSO terminal (ASIASSOCACHE…). The human keeps using their own cached SSO creds
# in their own shell; nothing they do by hand can ever land on the agent's key.
exec claude "$@"
