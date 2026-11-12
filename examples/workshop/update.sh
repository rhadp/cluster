#!/usr/bin/env bash

# Create a devspaces namespace for every workshop user by calling devspace.sh
# once per user. Usernames follow the create_workshop_setup role convention:
# <prefix><NN>, zero-padded to two digits (user01..user50).
#
# Override the defaults with the same env vars the role uses:
#   WORKSHOP_USER_COUNT  (default: 50)
#   WORKSHOP_USER_PREFIX (default: user)

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $(basename "$0") GITHUB_REPO GITHUB_PAT [UPSTREAM_REPO]" >&2
  echo "  GITHUB_REPO:   the repository to update, as owner/repo." >&2
  echo "  GITHUB_PAT:    the GitHub Personal Access Token (needs Contents: write on GITHUB_REPO)." >&2
  exit 1
fi

GIT_REPO=$1
GIT_PAT=$2

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

USER_COUNT=${WORKSHOP_USER_COUNT:-70}
USER_PREFIX=${WORKSHOP_USER_PREFIX:-user}

FAILED=()

for i in $(seq 1 "$USER_COUNT"); do
  USER_NAME=$(printf "%s%02d" "$USER_PREFIX" "$i")
  REPO_NAME="${GIT_REPO}-${USER_NAME}"

  echo "=== [$i/$USER_COUNT] $USER_NAME ==="
  
  if ! "$SCRIPT_DIR/update-repo.sh" "$REPO_NAME" "$GIT_PAT"; then
    echo "Error: update-repo.sh failed for $USER_NAME" >&2
    FAILED+=("$USER_NAME")
  fi

  sleep 3
done

echo "Done: repositories updated for $USER_COUNT users."
