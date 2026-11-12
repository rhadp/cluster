#!/usr/bin/env bash

# Update a GitHub repository from its upstream repository, using only the
# GitHub API (no local clone).
#
# The upstream is detected from the repository itself, unless given explicitly:
#   - fork                         -> upstream is the parent repository; the
#                                     default branch is synced with GitHub's
#                                     "merge upstream" API (fast-forward or merge).
#   - generated from a template    -> upstream is the template repository. The
#     (see buildspace.sh)             two repos share no git history, so the
#                                     template's current content is copied into a
#                                     new commit on top of the repo's default
#                                     branch. The result matches the template
#                                     exactly: files changed or added in the repo
#                                     are overwritten / removed (they remain in
#                                     the history).

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $(basename "$0") GITHUB_REPO GITHUB_PAT [UPSTREAM_REPO]" >&2
  echo "  GITHUB_REPO:   the repository to update, as owner/repo." >&2
  echo "  GITHUB_PAT:    the GitHub Personal Access Token (needs Contents: write on GITHUB_REPO)." >&2
  echo "  UPSTREAM_REPO: optional, owner/repo to update from. Defaults to the fork parent" >&2
  echo "                 or the template the repository was generated from." >&2
  exit 1
fi

GIT_REPO=$1
GIT_PAT=$2
UPSTREAM_REPO=${3:-}

API="https://api.github.com"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# gh_api METHOD PATH [JSON_FILE] -- print the response body; exit on HTTP errors
gh_api() {
  local method=$1 path=$2 data=${3:-}
  local args=(-sS --fail-with-body -X "$method"
    -H "Accept: application/vnd.github+json"
    -H "Authorization: Bearer ${GIT_PAT}"
    -H "X-GitHub-Api-Version: 2022-11-28")
  if [ -n "$data" ]; then
    args+=(-H "Content-Type: application/json" --data-binary "@$data")
  fi
  local body
  if ! body=$(curl "${args[@]}" "${API}${path}"); then
    echo "Error: $method $path failed:" >&2
    echo "$body" >&2
    exit 1
  fi
  printf '%s' "$body"
}

# --- inspect the repository -------------------------------------------------

gh_api GET "/repos/${GIT_REPO}" > "$WORK/repo.json"
BRANCH=$(jq -r '.default_branch' "$WORK/repo.json")
IS_FORK=$(jq -r '.fork' "$WORK/repo.json")

if [ -z "$UPSTREAM_REPO" ]; then
  UPSTREAM_REPO=$(jq -r '.parent.full_name // .template_repository.full_name // empty' "$WORK/repo.json")
fi
if [ -z "$UPSTREAM_REPO" ]; then
  echo "Error: ${GIT_REPO} is neither a fork nor generated from a template; pass UPSTREAM_REPO." >&2
  exit 1
fi

echo "Updating ${GIT_REPO} (${BRANCH}) from ${UPSTREAM_REPO}"

# --- forks: let GitHub do the merge ------------------------------------------

if [ "$IS_FORK" = "true" ] && [ "$UPSTREAM_REPO" = "$(jq -r '.parent.full_name' "$WORK/repo.json")" ]; then
  jq -n --arg branch "$BRANCH" '{branch: $branch}' > "$WORK/merge.json"
  gh_api POST "/repos/${GIT_REPO}/merge-upstream" "$WORK/merge.json" | jq -r '.message'
  exit 0
fi

# --- everything else: copy the upstream tree into a new commit ---------------

UP_BRANCH=$(gh_api GET "/repos/${UPSTREAM_REPO}" | jq -r '.default_branch')

gh_api GET "/repos/${UPSTREAM_REPO}/commits/${UP_BRANCH}" > "$WORK/up-commit.json"
UP_SHA=$(jq -r '.sha' "$WORK/up-commit.json")
UP_TREE=$(jq -r '.commit.tree.sha' "$WORK/up-commit.json")

gh_api GET "/repos/${GIT_REPO}/commits/${BRANCH}" > "$WORK/commit.json"
HEAD_SHA=$(jq -r '.sha' "$WORK/commit.json")
HEAD_TREE=$(jq -r '.commit.tree.sha' "$WORK/commit.json")

# git object ids are content hashes: equal tree ids mean identical content
if [ "$UP_TREE" = "$HEAD_TREE" ]; then
  echo "Already up to date with ${UPSTREAM_REPO}@${UP_SHA:0:7}"
  exit 0
fi

gh_api GET "/repos/${UPSTREAM_REPO}/git/trees/${UP_TREE}?recursive=1" > "$WORK/up-tree.json"
gh_api GET "/repos/${GIT_REPO}/git/trees/${HEAD_TREE}?recursive=1" > "$WORK/tree.json"
if [ "$(jq -r '.truncated' "$WORK/up-tree.json")" = "true" ] || [ "$(jq -r '.truncated' "$WORK/tree.json")" = "true" ]; then
  echo "Error: repository tree too large for the GitHub trees API" >&2
  exit 1
fi

# copy the blobs the repository does not have yet (same content = same sha)
jq -r '.tree[] | select(.type == "blob") | .sha' "$WORK/tree.json" | sort -u > "$WORK/have"
jq -r '.tree[] | select(.type == "blob") | .sha' "$WORK/up-tree.json" | sort -u > "$WORK/want"
MISSING=$(comm -13 "$WORK/have" "$WORK/want")

COUNT=$(printf '%s' "$MISSING" | grep -c . || true)
echo "Copying ${COUNT} new or changed file(s)..."
for sha in $MISSING; do
  gh_api GET "/repos/${UPSTREAM_REPO}/git/blobs/${sha}" \
    | jq '{content: (.content | gsub("\n"; "")), encoding: "base64"}' > "$WORK/blob.json"
  NEW_SHA=$(gh_api POST "/repos/${GIT_REPO}/git/blobs" "$WORK/blob.json" | jq -r '.sha')
  if [ "$NEW_SHA" != "$sha" ]; then
    echo "Error: blob ${sha} was stored as ${NEW_SHA}" >&2
    exit 1
  fi
done

# build the tree from the upstream file list (directories are implied by paths)
jq '{tree: [.tree[] | select(.type != "tree") | {path, mode, type, sha}]}' \
  "$WORK/up-tree.json" > "$WORK/new-tree.json"
NEW_TREE=$(gh_api POST "/repos/${GIT_REPO}/git/trees" "$WORK/new-tree.json" | jq -r '.sha')

jq -n --arg msg "chore: update from ${UPSTREAM_REPO}@${UP_SHA:0:7}" \
  --arg tree "$NEW_TREE" --arg parent "$HEAD_SHA" \
  '{message: $msg, tree: $tree, parents: [$parent]}' > "$WORK/new-commit.json"
NEW_COMMIT=$(gh_api POST "/repos/${GIT_REPO}/git/commits" "$WORK/new-commit.json" | jq -r '.sha')

# not forced: fails if the branch moved since we read it
jq -n --arg sha "$NEW_COMMIT" '{sha: $sha, force: false}' > "$WORK/ref.json"
gh_api PATCH "/repos/${GIT_REPO}/git/refs/heads/${BRANCH}" "$WORK/ref.json" > /dev/null

echo "Updated ${GIT_REPO} ${BRANCH}: ${HEAD_SHA:0:7} -> ${NEW_COMMIT:0:7} (${UPSTREAM_REPO}@${UP_SHA:0:7})"
