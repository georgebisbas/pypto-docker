#!/usr/bin/env bash
# Fast-forward local main from origin/<default-branch> for sibling repos without checkout/switch.
#
# Usage (from anywhere):
#   ./scripts/fetch-pull-mains.sh
#   bash /path/to/pypto-docker/scripts/fetch-pull-mains.sh
#
# Repos: pypto, pto-isa, PTOAS, pypto-lib (siblings of pypto-docker).
# PTOAS's upstream default branch is `master`, not `main` (renamed at some
# point after this script's local `main` clone was created) -- REPO_BRANCH
# below is the per-repo override for that.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REPOS=(pypto pto-isa PTOAS pypto-lib)
declare -A REPO_BRANCH=([PTOAS]=master)
FAILED=0

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'
else
  C_RESET= C_BOLD= C_RED= C_GREEN= C_YELLOW= C_CYAN= C_BLUE=
fi

ok()    { echo "${C_GREEN}$*${C_RESET}"; }
warn()  { echo "${C_YELLOW}$*${C_RESET}"; }
err()   { echo "${C_RED}ERROR:${C_RESET} $*" >&2; }
header(){ echo "${C_BOLD}${C_BLUE}=== $* ===${C_RESET}"; }

short_sha() {
  local repo="$1" ref="$2"
  git -C "${repo}" rev-parse --short "${ref}" 2>/dev/null || echo "missing"
}

update_repo() {
  local name="$1"
  local repo="${WORKSPACE_ROOT}/${name}"
  local remote_branch="${REPO_BRANCH[${name}]:-main}"

  header "${name}"

  if [[ ! -d "${repo}" ]]; then
    err "directory not found: ${repo}"
    return 1
  fi
  if [[ ! -d "${repo}/.git" ]] && ! git -C "${repo}" rev-parse --git-dir >/dev/null 2>&1; then
    err "not a git repository: ${repo}"
    return 1
  fi
  if ! git -C "${repo}" remote get-url origin >/dev/null 2>&1; then
    err "remote 'origin' not configured"
    return 1
  fi

  local before current
  before="$(short_sha "${repo}" refs/heads/main)"
  current="$(git -C "${repo}" branch --show-current)"

  echo "current branch: ${C_CYAN}${current:-DETACHED}${C_RESET}"
  echo "local main before: ${C_CYAN}${before}${C_RESET}"
  if [[ "${remote_branch}" != "main" ]]; then
    echo "upstream default branch: ${C_CYAN}${remote_branch}${C_RESET} (overridden; local branch stays 'main')"
  fi

  # Probe origin/<remote_branch> exists (fetch first so the ref is available).
  if ! git -C "${repo}" fetch origin "${remote_branch}"; then
    err "failed to fetch origin ${remote_branch}"
    return 1
  fi
  if ! git -C "${repo}" show-ref --verify --quiet "refs/remotes/origin/${remote_branch}"; then
    err "origin/${remote_branch} does not exist"
    return 1
  fi

  # Diverged (not a fast-forward) needs a human decision -- report and move on
  # rather than mask it as a generic ff-only failure.
  if ! git -C "${repo}" merge-base --is-ancestor main "origin/${remote_branch}"; then
    local ahead behind
    ahead="$(git -C "${repo}" rev-list --count "main..origin/${remote_branch}")"
    behind="$(git -C "${repo}" rev-list --count "origin/${remote_branch}..main")"
    err "local main has diverged from origin/${remote_branch} (${ahead} commits behind, ${behind} commits ahead) -- needs manual reconciliation, not auto-fast-forwarded"
    return 1
  fi

  if [[ "${current}" == "main" ]]; then
    if ! git -C "${repo}" merge --ff-only "origin/${remote_branch}"; then
      err "fast-forward merge of origin/${remote_branch} into main failed"
      return 1
    fi
  else
    # Update local main without checking it out (refuses non-FF).
    if ! git -C "${repo}" fetch origin "${remote_branch}:main"; then
      err "failed to fast-forward local main from origin/${remote_branch}"
      return 1
    fi
  fi

  local after head_now
  after="$(short_sha "${repo}" refs/heads/main)"
  head_now="$(git -C "${repo}" branch --show-current || echo DETACHED)"
  echo "local main after:  ${C_CYAN}${after}${C_RESET}"
  if [[ "${before}" == "${after}" ]]; then
    warn "status: already up to date"
  else
    ok "status: updated ${before} -> ${after}"
  fi
  echo "HEAD unchanged: ${C_CYAN}${head_now}${C_RESET}"
}

for name in "${REPOS[@]}"; do
  if ! update_repo "${name}"; then
    FAILED=1
  fi
  echo
done

if [[ "${FAILED}" -ne 0 ]]; then
  echo "${C_RED}${C_BOLD}Done with errors.${C_RESET}"
  exit 1
fi
echo "${C_GREEN}${C_BOLD}Done. All mains updated (or already up to date).${C_RESET}"
