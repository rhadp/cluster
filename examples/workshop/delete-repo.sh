#!/usr/bin/env bash

# Delete a GitHub repository using the GitHub API.
#
# - A repository that does not exist is skipped (exit 0), so re-runs are safe.
# - Template repositories are never deleted, to protect the upstream that
#   buildspace.sh generates the workshop repositories from.
#
# The PAT needs permission to delete the repository: "Administration: write"
# (fine-grained token) or the "delete_repo" scope (classic token).

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $(basename "$0") GITHUB_REPO GITHUB_PAT" >&2
  echo "  GITHUB_REPO: the repository to delete, as owner/repo." >&2
  echo "  GITHUB_PAT:  the GitHub Personal Access Token (needs Administration: write / delete_repo)." >&2
  exit 1
fi

GIT_REPO=$1
GIT_PAT=$2

API="https://api.github.com"

# gh_api METHOD PATH -- sets STATUS (HTTP code) and BODY (response body)
gh_api() {
  local method=$1 path=$2 resp
  resp=$(curl -sS -X "$method" -w $'\n%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GIT_PAT}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API}${path}")
  STATUS=${resp##*$'\n'}
  BODY=${resp%$'\n'*}
}

gh_api GET "/repos/${GIT_REPO}"
case "$STATUS" in
  200) ;;
  404)
    echo "Repository ${GIT_REPO} does not exist (or the PAT cannot see it), skipping"
    exit 0
    ;;
  *)
    echo "Error: GET /repos/${GIT_REPO} failed (HTTP ${STATUS}):" >&2
    echo "$BODY" >&2
    exit 1
    ;;
esac

if [ "$(echo "$BODY" | jq -r '.is_template')" = "true" ]; then
  echo "Error: ${GIT_REPO} is a template repository, refusing to delete it" >&2
  exit 1
fi

gh_api DELETE "/repos/${GIT_REPO}"
if [ "$STATUS" != "204" ]; then
  echo "Error: DELETE /repos/${GIT_REPO} failed (HTTP ${STATUS}):" >&2
  echo "$BODY" >&2
  exit 1
fi

echo "Deleted ${GIT_REPO}"
