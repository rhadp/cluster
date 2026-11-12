#!/usr/bin/env bash

# Delete the GitHub repository of every workshop user by calling delete-repo.sh
# once per user. Repository names follow the buildspace.sh convention:
# <GITHUB_REPO>-<prefix><NN>, zero-padded to two digits (user01..user70).
#
# Asks for confirmation first; set WORKSHOP_ASSUME_YES=1 to skip the prompt.
#
# Override the defaults with the same env vars the role uses:
#   WORKSHOP_USER_COUNT  (default: 70)
#   WORKSHOP_USER_PREFIX (default: user)

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $(basename "$0") GITHUB_REPO GITHUB_PAT" >&2
  echo "  GITHUB_REPO: the upstream repository the user repos were created from, as owner/repo." >&2
  echo "  GITHUB_PAT:  the GitHub Personal Access Token (needs Administration: write / delete_repo)." >&2
  exit 1
fi

GIT_REPO=$1
GIT_PAT=$2

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

USER_COUNT=${WORKSHOP_USER_COUNT:-59}
USER_PREFIX=${WORKSHOP_USER_PREFIX:-user}

FIRST=$(printf "%s-%s%02d" "$GIT_REPO" "$USER_PREFIX" 1)
LAST=$(printf "%s-%s%02d" "$GIT_REPO" "$USER_PREFIX" "$USER_COUNT")

FAILED=()

for i in $(seq 56 "$USER_COUNT"); do
  USER_NAME=$(printf "%s%02d" "$USER_PREFIX" "$i")
  REPO_NAME="${GIT_REPO}-${USER_NAME}"

  echo "=== [$i/$USER_COUNT] $USER_NAME ==="

  if ! "$SCRIPT_DIR/delete-repo.sh" "$REPO_NAME" "$GIT_PAT"; then
    echo "Error: delete-repo.sh failed for $USER_NAME" >&2
    FAILED+=("$USER_NAME")
  fi

  sleep 3
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "Failed for ${#FAILED[@]} user(s): ${FAILED[*]}" >&2
  exit 1
fi

echo "Done: repositories deleted for $USER_COUNT users."
