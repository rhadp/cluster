#!/usr/bin/env bash

# Update a GitHub repository from its upstream repository, using only the
# GitHub API (no local clone).
#
# The upstream is detected from the repository itself, unless given explicitly:
#   - fork                         -> upstream is the parent repository; the
#                                     default branch is synced with GitHub's
#                                     "merge upstream" API (fast-forward or merge).
#   - generated from a template    -> upstream is the template repository. The
#     (see buildspace.sh)             two repos share no git history, so every
#                                     upstream commit the repo does not have yet
#                                     is replayed, one by one, on top of the
#                                     repo's default branch, keeping its message
#                                     and author (plus an Upstream-Commit trailer).
#
# For templates, the last upstream commit already in the repo is found by
# content: the newest commit on the upstream's first-parent history whose tree
# also appears in the repo's history (the "Initial commit" of a generated repo,
# or a commit made by an earlier run). Only the commits after it are replayed;
# side branches merged upstream arrive as their merge commit. If the repo has
# changes of its own, a "chore: reset" commit first restores that upstream
# state, so each replayed commit carries exactly the upstream change. The
# result matches the template exactly: files changed or added in the repo are
# overwritten / removed (they remain in the history).

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

# --- everything else: replay the upstream commits ----------------------------

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

# list_commits REPO SHA PAGE -- one page (100) of the history reachable from
# SHA, as TSV lines: sha, tree, first parent ("-" for a root commit)
list_commits() {
  gh_api GET "/repos/$1/commits?sha=$2&per_page=100&page=$3" \
    | jq -r '.[] | [.sha, .commit.tree.sha, (.parents[0].sha // "-")] | @tsv'
}

# every tree in the repo's history
: > "$WORK/trees"
page=1
while :; do
  list_commits "$GIT_REPO" "$HEAD_SHA" "$page" > "$WORK/page"
  cut -f2 "$WORK/page" >> "$WORK/trees"
  [ "$(wc -l < "$WORK/page")" -lt 100 ] && break
  page=$((page + 1))
done

# up_lookup SHA -- set C_TREE / C_PARENT for an upstream commit, fetching more
# upstream history as needed
: > "$WORK/up-commits"
UP_PAGE=0
UP_DONE=false
up_lookup() {
  local line
  while ! line=$(grep -m1 "^$1"$'\t' "$WORK/up-commits"); do
    if [ "$UP_DONE" = true ]; then
      echo "Error: commit $1 not found in ${UPSTREAM_REPO}'s history" >&2
      exit 1
    fi
    UP_PAGE=$((UP_PAGE + 1))
    list_commits "$UPSTREAM_REPO" "$UP_SHA" "$UP_PAGE" > "$WORK/page"
    cat "$WORK/page" >> "$WORK/up-commits"
    if [ "$(wc -l < "$WORK/page")" -lt 100 ]; then UP_DONE=true; fi
  done
  C_TREE=$(printf '%s\n' "$line" | cut -f2)
  C_PARENT=$(printf '%s\n' "$line" | cut -f3)
}

# walk the upstream first-parent history back to the newest commit whose
# content the repo already has; everything above it is new
BASE=""
BASE_TREE=""
: > "$WORK/chain"   # new upstream commits, newest first
cur=$UP_SHA
while [ "$cur" != "-" ]; do
  up_lookup "$cur"
  if grep -qxF "$C_TREE" "$WORK/trees"; then
    BASE=$cur
    BASE_TREE=$C_TREE
    break
  fi
  echo "$cur" >> "$WORK/chain"
  cur=$C_PARENT
done

# the upstream commits whose content becomes a new commit, oldest first;
# the first one is a reset when the repo's content differs from it
RESET=""
RESET_MSG=""
if [ -z "$BASE" ]; then
  echo "Warning: ${GIT_REPO} has no content in common with ${UPSTREAM_REPO}'s history;" >&2
  echo "         copying ${UPSTREAM_REPO}@${UP_SHA:0:7} as a single commit." >&2
  RESET=$UP_SHA
  RESET_MSG="chore: update from ${UPSTREAM_REPO}@${UP_SHA:0:7}"
  : > "$WORK/chain"
elif [ "$BASE_TREE" != "$HEAD_TREE" ]; then
  RESET=$BASE
  RESET_MSG="chore: reset to ${UPSTREAM_REPO}@${BASE:0:7}"
fi
{
  if [ -n "$RESET" ]; then echo "$RESET"; fi
  awk '{ line[NR] = $0 } END { for (i = NR; i > 0; i--) print line[i] }' "$WORK/chain"
} > "$WORK/targets"

REPLAY=$(grep -c . "$WORK/chain" || true)
if [ -n "$BASE" ]; then
  echo "Last upstream commit in ${GIT_REPO}: ${UPSTREAM_REPO}@${BASE:0:7}"
fi
if [ "$RESET" = "$BASE" ] && [ -n "$BASE" ]; then
  echo "${GIT_REPO} has changes of its own; they are reset first"
fi
echo "Replaying ${REPLAY} upstream commit(s) on top of ${HEAD_SHA:0:7}"

# fetch each target's commit and file list
: > "$WORK/want"
while read -r sha; do
  gh_api GET "/repos/${UPSTREAM_REPO}/git/commits/${sha}" > "$WORK/c-${sha}.json"
  tree=$(jq -r '.tree.sha' "$WORK/c-${sha}.json")
  gh_api GET "/repos/${UPSTREAM_REPO}/git/trees/${tree}?recursive=1" > "$WORK/t-${sha}.json"
  if [ "$(jq -r '.truncated' "$WORK/t-${sha}.json")" = "true" ]; then
    echo "Error: tree of ${UPSTREAM_REPO}@${sha:0:7} too large for the GitHub trees API" >&2
    exit 1
  fi
  jq -r '.tree[] | select(.type == "blob") | .sha' "$WORK/t-${sha}.json" >> "$WORK/want"
done < "$WORK/targets"

# copy the blobs the repository does not have yet (same content = same sha)
gh_api GET "/repos/${GIT_REPO}/git/trees/${HEAD_TREE}?recursive=1" > "$WORK/tree.json"
jq -r '.tree[] | select(.type == "blob") | .sha' "$WORK/tree.json" | sort -u > "$WORK/have"
sort -u -o "$WORK/want" "$WORK/want"
MISSING=$(comm -13 "$WORK/have" "$WORK/want")

COUNT=$(printf '%s' "$MISSING" | grep -c . || true)
echo "Copying ${COUNT} new or changed file version(s)..."
for sha in $MISSING; do
  gh_api GET "/repos/${UPSTREAM_REPO}/git/blobs/${sha}" \
    | jq '{content: (.content | gsub("\n"; "")), encoding: "base64"}' > "$WORK/blob.json"
  NEW_SHA=$(gh_api POST "/repos/${GIT_REPO}/git/blobs" "$WORK/blob.json" | jq -r '.sha')
  if [ "$NEW_SHA" != "$sha" ]; then
    echo "Error: blob ${sha} was stored as ${NEW_SHA}" >&2
    exit 1
  fi
done

# one commit per target, each on top of the previous one
PARENT=$HEAD_SHA
while read -r sha; do
  # build the tree from the upstream file list (directories are implied by paths)
  jq '{tree: [.tree[] | select(.type != "tree") | {path, mode, type, sha}]}' \
    "$WORK/t-${sha}.json" > "$WORK/new-tree.json"
  NEW_TREE=$(gh_api POST "/repos/${GIT_REPO}/git/trees" "$WORK/new-tree.json" | jq -r '.sha')
  if [ "$NEW_TREE" != "$(jq -r '.tree.sha' "$WORK/c-${sha}.json")" ]; then
    echo "Error: tree of ${UPSTREAM_REPO}@${sha:0:7} was stored as ${NEW_TREE}" >&2
    exit 1
  fi

  if [ "$sha" = "$RESET" ] && [ "$PARENT" = "$HEAD_SHA" ]; then
    jq -n --arg msg "$RESET_MSG" --arg tree "$NEW_TREE" --arg parent "$PARENT" \
      '{message: $msg, tree: $tree, parents: [$parent]}' > "$WORK/new-commit.json"
  else
    # same message and author; the committer is the token's user
    jq --arg tree "$NEW_TREE" --arg parent "$PARENT" \
      --arg trailer "Upstream-Commit: ${UPSTREAM_REPO}@${sha}" \
      '{message: ((.message | sub("\\s+$"; "")) + "\n\n" + $trailer + "\n"),
        tree: $tree, parents: [$parent],
        author: (.author | {name, email, date})}' \
      "$WORK/c-${sha}.json" > "$WORK/new-commit.json"
  fi
  PARENT=$(gh_api POST "/repos/${GIT_REPO}/git/commits" "$WORK/new-commit.json" | jq -r '.sha')
  echo "  ${sha:0:7} -> ${PARENT:0:7}  $(jq -r '.message | split("\n")[0]' "$WORK/new-commit.json")"
done < "$WORK/targets"

# not forced: fails if the branch moved since we read it
jq -n --arg sha "$PARENT" '{sha: $sha, force: false}' > "$WORK/ref.json"
gh_api PATCH "/repos/${GIT_REPO}/git/refs/heads/${BRANCH}" "$WORK/ref.json" > /dev/null

echo "Updated ${GIT_REPO} ${BRANCH}: ${HEAD_SHA:0:7} -> ${PARENT:0:7} (${UPSTREAM_REPO}@${UP_SHA:0:7})"
