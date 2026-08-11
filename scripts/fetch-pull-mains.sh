#!/usr/bin/env bash
# Fast-forward local main from origin/main for sibling repos without checkout/switch.
#
# Usage (from anywhere):
#   ./scripts/fetch-pull-mains.sh
#   bash /path/to/pypto-tooling/scripts/fetch-pull-mains.sh
#
# Repos: pypto, pto-isa, PTOAS, pypto-lib (siblings of pypto-tooling).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REPOS=(pypto pto-isa PTOAS pypto-lib)
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

  # Probe origin/main exists (fetch first so the ref is available).
  if ! git -C "${repo}" fetch origin main; then
    err "failed to fetch origin main"
    return 1
  fi
  if ! git -C "${repo}" show-ref --verify --quiet refs/remotes/origin/main; then
    err "origin/main does not exist"
    return 1
  fi

  if [[ "${current}" == "main" ]]; then
    if ! git -C "${repo}" merge --ff-only origin/main; then
      err "fast-forward merge of origin/main into main failed"
      return 1
    fi
  else
    # Update local main without checking it out (refuses non-FF).
    if ! git -C "${repo}" fetch origin main:main; then
      err "failed to fast-forward local main from origin/main"
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
