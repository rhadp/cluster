#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $(basename "$0") GITHUB_REPO GITHUB_PAT [UPSTREAM_REPO]" >&2
  echo "  GITHUB_REPO:   the repository to update, as owner/repo." >&2
  echo "  GITHUB_PAT:    the GitHub Personal Access Token (needs Contents: write on GITHUB_REPO)." >&2
  exit 1
fi

GIT_REPO=$1
GIT_PAT=$2

# some endpoints
CONSOLE_URL=$(oc whoami --show-console)
BASE_URL=${CONSOLE_URL#https://console-openshift-console.}

API="https://api.github.com"

# NAMESPACE normalization for use in kubernetes
NAMESPACE=buildspace-$(echo "$GIT_REPO" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9-]/-/g; s/-\+/-/g; s/^-//; s/-$//' | cut -c1-63)

# prepare for PAC setup
PAC_ENDPOINT="https://pipelines-as-code-controller-openshift-pipelines.$BASE_URL"

# Create the webhook secret and create the webhook config secret
WEBHOOK_SECRET=$(openssl rand -hex 20)

if oc get secret github-webhook-config -n "$NAMESPACE" &>/dev/null; then
  oc delete secret github-webhook-config -n "$NAMESPACE"
  echo "Waiting for secret github-webhook-config to be deleted..."
  sleep 10
fi

oc -n $NAMESPACE create secret generic github-webhook-config \
  --from-literal provider.token="$GIT_PAT" \
  --from-literal webhook.secret="$WEBHOOK_SECRET"

# PAC endpoint setup

# create the webhook
HOOK_EXISTS=$(curl -sS \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GIT_PAT}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${GIT_REPO}/hooks" \
  | jq -e --arg url "$PAC_ENDPOINT" '.[] | select(.config.url == $url)')

if [[ -n "$HOOK_EXISTS" ]]; then
  echo "Webhook already exists, deleting it"
  HOOK_ID=$(echo "$HOOK_EXISTS" | jq -r '.id')
  curl -sS -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GIT_PAT}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GIT_REPO}/hooks/${HOOK_ID}"
fi

echo "Creating webhook..."

curl -sS -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GIT_PAT}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${GIT_REPO}/hooks" \
  -d @- <<EOF
{
  "name": "web",
  "active": true,
  "events": ["push", "pull_request", "issue_comment", "commit_comment"],
  "config": {
    "url": "${PAC_ENDPOINT}",
    "content_type": "json",
    "insecure_ssl": "0",
    "secret": "${WEBHOOK_SECRET}"
  }
}
EOF
