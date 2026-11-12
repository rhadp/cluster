#!/usr/bin/env bash

# Create a devspaces namespace for every workshop user by calling devspace.sh
# once per user. Usernames follow the create_workshop_setup role convention:
# <prefix><NN>, zero-padded to two digits (user01..user50).
#
# Override the defaults with the same env vars the role uses:
#   WORKSHOP_USER_COUNT  (default: 50)
#   WORKSHOP_USER_PREFIX (default: user)

set -u

if [ "$#" -ne 3 ]; then
  echo "Usage: $(basename "$0") GITHUB_REPO GITHUB_PAT GITHUB_USER_PAT" >&2
  echo "  GITHUB_REPO: the GitHub repository to use for setting up the buildspace." >&2
  echo "  GITHUB_PAT: the Admin GitHub Personal Access Token to use for setting up the buildspace." >&2
  echo "  GITHUB_USER_PAT: the User GitHub Personal Access Token to use for setting up the buildspace." >&2
  exit 1
fi

GIT_REPO=$1
GIT_PAT=$2
GITHUB_USER_PAT=$3

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

USER_COUNT=${WORKSHOP_USER_COUNT:-70}
USER_PREFIX=${WORKSHOP_USER_PREFIX:-user}

FAILED=()

for i in $(seq 1 "$USER_COUNT"); do
  USER_NAME=$(printf "%s%02d" "$USER_PREFIX" "$i")
  echo "=== [$i/$USER_COUNT] $USER_NAME ==="
  
  if ! "$SCRIPT_DIR/buildspace.sh" "$GIT_REPO" "$GIT_PAT" "$USER_NAME"; then
    echo "Error: buildspace.sh failed for $USER_NAME" >&2
    FAILED+=("$USER_NAME")
  fi

  if ! "$SCRIPT_DIR/devspace.sh" "$USER_NAME"; then
    echo "Error: devspace.sh failed for $USER_NAME" >&2
    FAILED+=("$USER_NAME")
  fi

  if ! "$SCRIPT_DIR/devspace-config.sh" "$USER_NAME" "$GITHUB_USER_PAT"; then
    echo "Error: devspace-config.sh failed for $USER_NAME" >&2
    FAILED+=("$USER_NAME")
  fi

done

echo "Done: buildspaces and devspaces namespaces created for $USER_COUNT users."
