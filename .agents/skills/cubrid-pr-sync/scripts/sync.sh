#!/usr/bin/env bash

set -euo pipefail

readonly ENGINE_UPSTREAM="CUBRID/cubrid"
readonly PUBLIC_TC_REPO="CUBRID/cubrid-testcases"
readonly PRIVATE_TC_REPO="CUBRID/cubrid-testcases-private-ex"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s <CUBRID-PR-number-or-URL>\n' "${0##*/}" >&2
  exit 2
}

parse_pr_number() {
  local input=$1

  if [[ "$input" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$input"
    return
  fi

  if [[ "$input" =~ ^https://github\.com/[Cc][Uu][Bb][Rr][Ii][Dd]/cubrid/pull/([0-9]+)/?([?#].*)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  die "expected a PR number or https://github.com/CUBRID/cubrid/pull/<number>"
}

branch_sha() {
  local repo=$1
  local branch=$2
  gh api "repos/$repo/branches/$branch" --jq '.commit.sha'
}

require_push_access() {
  local repo=$1
  local can_push
  can_push=$(gh api "repos/$repo" --jq '.permissions.push')
  [[ "$can_push" == "true" ]] || die "authenticated user cannot push to $repo"
}

behind_by() {
  local repo=$1
  local develop_sha=$2
  local branch_tip=$3
  gh api "repos/$repo/compare/$develop_sha...$branch_tip" --jq '.behind_by'
}

merge_develop() {
  local label=$1
  local repo=$2
  local branch=$3
  local develop_sha=$4
  local old_tip=$5
  local behind=$6
  local message=$7
  local new_tip

  if [[ "$behind" == "0" ]]; then
    printf 'SKIPPED  %-10s %s:%s already contains develop %s\n' \
      "$label" "$repo" "$branch" "${develop_sha:0:12}"
    return
  fi

  printf 'MERGING  %-10s %s:%s (%s commit(s) behind)\n' \
    "$label" "$repo" "$branch" "$behind"
  gh api --method POST "repos/$repo/merges" \
    -f base="$branch" \
    -f head="$develop_sha" \
    -f commit_message="$message" \
    --silent || die "merge failed for $repo:$branch; earlier repositories may already be updated"

  new_tip=$(branch_sha "$repo" "$branch")
  printf 'MERGED   %-10s %s -> %s\n' "$label" "${old_tip:0:12}" "${new_tip:0:12}"
}

verify_contains_develop() {
  local label=$1
  local repo=$2
  local branch=$3
  local develop_sha=$4
  local current_tip current_behind

  current_tip=$(branch_sha "$repo" "$branch")
  current_behind=$(behind_by "$repo" "$develop_sha" "$current_tip")
  [[ "$current_behind" == "0" ]] || die "$repo:$branch does not contain pinned develop $develop_sha"
  printf 'VERIFIED %-10s head=%s develop=%s\n' \
    "$label" "${current_tip:0:12}" "${develop_sha:0:12}"
}

main() {
  [[ $# -eq 1 ]] || usage

  local pr_number pr_fields state base_ref engine_repo engine_branch pr_url tc_branch
  local engine_develop public_develop private_develop
  local engine_tip public_tip private_tip
  local engine_behind public_behind private_behind
  local -a fields

  pr_number=$(parse_pr_number "$1")
  command -v gh >/dev/null 2>&1 || die "gh is required"

  pr_fields=$(gh api "repos/$ENGINE_UPSTREAM/pulls/$pr_number" \
    --jq '.state, .base.ref, (.head.repo.full_name // ""), .head.ref, .html_url') \
    || die "cannot read $ENGINE_UPSTREAM PR #$pr_number"
  mapfile -t fields <<< "$pr_fields"
  state=${fields[0]:-}
  base_ref=${fields[1]:-}
  engine_repo=${fields[2]:-}
  engine_branch=${fields[3]:-}
  pr_url=${fields[4]:-}

  [[ "$state" == "open" ]] || die "$pr_url is not open"
  [[ "$base_ref" == "develop" ]] || die "$pr_url targets '$base_ref', not 'develop'"
  [[ -n "$engine_repo" ]] || die "$pr_url has no accessible head repository"

  tc_branch="tc/pr-$pr_number"

  printf 'Preflight: %s\n' "$pr_url"
  require_push_access "$engine_repo"
  require_push_access "$PUBLIC_TC_REPO"
  require_push_access "$PRIVATE_TC_REPO"

  engine_develop=$(branch_sha "$ENGINE_UPSTREAM" develop)
  public_develop=$(branch_sha "$PUBLIC_TC_REPO" develop)
  private_develop=$(branch_sha "$PRIVATE_TC_REPO" develop)
  engine_tip=$(branch_sha "$engine_repo" "$engine_branch")
  public_tip=$(branch_sha "$PUBLIC_TC_REPO" "$tc_branch")
  private_tip=$(branch_sha "$PRIVATE_TC_REPO" "$tc_branch")

  engine_behind=$(behind_by "$engine_repo" "$engine_develop" "$engine_tip")
  public_behind=$(behind_by "$PUBLIC_TC_REPO" "$public_develop" "$public_tip")
  private_behind=$(behind_by "$PRIVATE_TC_REPO" "$private_develop" "$private_tip")

  printf 'Pinned develop: engine=%s public-tc=%s private-tc=%s\n' \
    "${engine_develop:0:12}" "${public_develop:0:12}" "${private_develop:0:12}"

  merge_develop engine "$engine_repo" "$engine_branch" "$engine_develop" "$engine_tip" "$engine_behind" \
    "Merge CUBRID/develop into $engine_branch"
  merge_develop public-tc "$PUBLIC_TC_REPO" "$tc_branch" "$public_develop" "$public_tip" "$public_behind" \
    "Merge develop into $tc_branch"
  merge_develop private-tc "$PRIVATE_TC_REPO" "$tc_branch" "$private_develop" "$private_tip" "$private_behind" \
    "Merge develop into $tc_branch"

  verify_contains_develop engine "$engine_repo" "$engine_branch" "$engine_develop"
  verify_contains_develop public-tc "$PUBLIC_TC_REPO" "$tc_branch" "$public_develop"
  verify_contains_develop private-tc "$PRIVATE_TC_REPO" "$tc_branch" "$private_develop"
  printf 'DONE: branches are synchronized; CI completion was not awaited.\n'
}

main "$@"
