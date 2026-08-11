#!/usr/bin/env bash
# Build personal dev-layer images on top of the Ascend 910B (CANN) images,
# baking in git identity / fork remote / editable installs from
# pypto-tooling/personal_setup.md so `docker run` drops you into a
# ready-to-hack checkout. Run on the NPU host, after the base images exist
# (see build-npu-images.sh).
#
# Usage:
#   ./scripts/build-npu-dev-images.sh [pypto|simpler|all]
#
# Env overrides (only applied if non-empty; otherwise Dockerfile defaults apply):
#   GIT_USER_NAME      git identity baked into both images
#   GIT_USER_EMAIL     git identity baked into both images
#   FORK_REMOTE_NAME   fork remote name                    (pypto: default fork-gbisbas)
#   FORK_REMOTE_URL    fork remote URL to add + fetch       (pypto: default set; simpler: none by default)
#   PYPTO_BASE_IMAGE   base image tag for pypto, default pypto3-hw-native-sys:cann9
#   SIMPLER_BASE_IMAGE base image tag for simpler, default simpler-cann9
#
# Images:
#   pypto3-dev:cann9   <- Dockerfile.hw-native-sys.dev.cann9.0  (FROM ${PYPTO_BASE_IMAGE})
#   simpler-dev:cann9  <- Dockerfile.simpler.dev.cann9.0        (FROM ${SIMPLER_BASE_IMAGE})

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${1:-all}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET= C_BOLD= C_RED= C_GREEN= C_YELLOW= C_BLUE=
fi

ok()    { echo "${C_GREEN}$*${C_RESET}"; }
warn()  { echo "${C_YELLOW}$*${C_RESET}"; }
err()   { echo "${C_RED}ERROR:${C_RESET} $*" >&2; }
header(){ echo "${C_BOLD}${C_BLUE}=== $* ===${C_RESET}"; }

case "${TARGET}" in
  pypto|simpler|all) ;;
  *)
    echo "Usage: $0 [pypto|simpler|all]" >&2
    exit 2
    ;;
esac

command -v docker >/dev/null 2>&1 || { err "docker not found on PATH"; exit 1; }

cd "${TOOLING_DIR}"

image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

build_image() {
  local name="$1" dockerfile="$2" tag="$3" base_image="$4"
  shift 4
  local build_args=("$@")

  if ! image_exists "${base_image}"; then
    err "base image '${base_image}' not found locally — build it first with ./scripts/build-npu-images.sh ${name}"
    return 1
  fi

  header "${name} dev (${tag}, base=${base_image})"
  ((${#build_args[@]})) && printf 'build-arg:  %s\n' "${build_args[@]}"

  if docker build --build-arg "BASE_IMAGE=${base_image}" "${build_args[@]}" -t "${tag}" -f "${dockerfile}" .; then
    ok "built ${tag}"
  else
    err "build failed: ${tag}"
    return 1
  fi
}

FAILED=0

if [[ "${TARGET}" == "pypto" || "${TARGET}" == "all" ]]; then
  args=()
  [[ -n "${GIT_USER_NAME:-}" ]] && args+=(--build-arg "GIT_USER_NAME=${GIT_USER_NAME}")
  [[ -n "${GIT_USER_EMAIL:-}" ]] && args+=(--build-arg "GIT_USER_EMAIL=${GIT_USER_EMAIL}")
  [[ -n "${FORK_REMOTE_NAME:-}" ]] && args+=(--build-arg "FORK_REMOTE_NAME=${FORK_REMOTE_NAME}")
  [[ -n "${FORK_REMOTE_URL:-}" ]] && args+=(--build-arg "FORK_REMOTE_URL=${FORK_REMOTE_URL}")
  build_image "pypto" "Dockerfile.hw-native-sys.dev.cann9.0" "pypto3-dev:cann9" "${PYPTO_BASE_IMAGE:-pypto3-hw-native-sys:cann9}" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${TARGET}" == "simpler" || "${TARGET}" == "all" ]]; then
  args=()
  [[ -n "${GIT_USER_NAME:-}" ]] && args+=(--build-arg "GIT_USER_NAME=${GIT_USER_NAME}")
  [[ -n "${GIT_USER_EMAIL:-}" ]] && args+=(--build-arg "GIT_USER_EMAIL=${GIT_USER_EMAIL}")
  [[ -n "${FORK_REMOTE_NAME:-}" ]] && args+=(--build-arg "FORK_REMOTE_NAME=${FORK_REMOTE_NAME}")
  [[ -n "${FORK_REMOTE_URL:-}" ]] && args+=(--build-arg "FORK_REMOTE_URL=${FORK_REMOTE_URL}")
  build_image "simpler" "Dockerfile.simpler.dev.cann9.0" "simpler-dev:cann9" "${SIMPLER_BASE_IMAGE:-simpler-cann9}" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${FAILED}" -ne 0 ]]; then
  echo "${C_RED}${C_BOLD}Done with errors.${C_RESET}"
  exit 1
fi
echo "${C_GREEN}${C_BOLD}Done. Dev image(s) built.${C_RESET}"
echo "Run e.g. (same flags as the base cann9 images, see their RUN sections):"
echo "  docker run --rm -it --privileged --ipc=host -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro -v /dev:/dev pypto3-dev:cann9"
echo "  docker run --rm -it --privileged --ipc=host -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro -v /dev:/dev simpler-dev:cann9"
